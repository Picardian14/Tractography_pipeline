#!/usr/bin/env python3
"""Organize dcm2bids-helper output into a small BIDS-compatible layout.

The script processes every ``sub-*`` directory below ``bids_root`` independently
and writes into ``ses-1`` by default. It identifies T1w and DWI acquisitions
from their dcm2niix JSON metadata and:

* gives T1w and the original diffusion series standard names in ``anat/`` and
  ``dwi/``; and
* preserves every other imaging acquisition in ``other/`` with its dcm2niix
  filename.

This mirrors the existing DOC MRI dataset convention and keeps FLAIR, SWI, T2,
reverse B0, and scanner-generated imaging derivatives from being discarded.
Localizers, scouts, and secondary screenshots are omitted, as in the reference
dataset. After a subject is organized successfully, its temporary helper and
log directories are removed. Nothing is changed unless ``--apply`` is supplied.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path


NIFTI_EXTENSIONS = (".nii.gz", ".json")
DWI_EXTENSIONS = (".nii.gz", ".json", ".bval", ".bvec")


def strip_extension(path: Path, extension: str) -> str:
    if not path.name.endswith(extension):
        raise ValueError(f"{path} does not end in {extension}")
    return path.name[: -len(extension)]


def find_helper(subject_dir: Path) -> Path | None:
    candidates = (
        subject_dir / "tmp_dcm2bids" / "helper",
        subject_dir / "helper",
    )
    existing = [path for path in candidates if path.is_dir()]
    if len(existing) > 1:
        names = ", ".join(str(path) for path in existing)
        raise ValueError(f"found multiple helper directories: {names}")
    return existing[0] if existing else None


def read_series(helper: Path) -> list[dict]:
    """Load paired NIfTI/JSON outputs and the metadata used for classification."""
    series = []
    for json_path in sorted(helper.glob("*.json")):
        prefix = strip_extension(json_path, ".json")
        nii_path = helper / f"{prefix}.nii.gz"
        if not nii_path.is_file():
            continue
        try:
            metadata = json.loads(json_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"cannot read {json_path.name}: {error}") from error

        image_type = {str(value).upper() for value in metadata.get("ImageType", [])}
        description = " ".join(
            str(metadata.get(key, ""))
            for key in ("SeriesDescription", "ProtocolName")
        )
        text = f"{prefix} {description}"
        bval_path = helper / f"{prefix}.bval"
        bvals = None
        if bval_path.is_file():
            try:
                bvals = [float(value) for value in bval_path.read_text().split()]
            except (OSError, ValueError) as error:
                raise ValueError(f"cannot read {bval_path.name}: {error}") from error

        series.append(
            {
                "prefix": prefix,
                "helper": helper,
                "metadata": metadata,
                "image_type": image_type,
                "text": text,
                "bvals": bvals,
            }
        )
    return series


def is_original(item: dict) -> bool:
    image_type = item["image_type"]
    return "DERIVED" not in image_type and "SECONDARY" not in image_type


def preserve_under_other(item: dict) -> bool:
    """Keep useful acquisitions while dropping localizers and screenshots."""
    if contains(
        item["text"],
        r"(?:^|[^a-z0-9])(?:scout|locali[sz]er)(?:[^a-z0-9]|$)",
    ):
        return False
    image_type = item["image_type"]
    return "SECONDARY" not in image_type and "SPECTROSCOPY" not in image_type


def contains(text: str, pattern: str) -> bool:
    return re.search(pattern, text, flags=re.IGNORECASE) is not None


def classify_series(series: list[dict]) -> dict[str, list[dict]]:
    acquisitions: dict[str, list[dict]] = {
        "dwi": [],
        "T1w": [],
    }
    for item in series:
        if not is_original(item):
            continue

        text = item["text"]
        image_type = item["image_type"]
        bvals = item["bvals"]
        is_diffusion = "DIFFUSION" in image_type or contains(text, r"\bdiff(?:usion)?\b")

        # A true DWI contains diffusion-weighted volumes. An all-b=0 series is
        # preserved under other/ with its original name instead.
        if is_diffusion and bvals and any(abs(value) > 50 for value in bvals):
            acquisitions["dwi"].append(item)
        elif contains(text, r"(?:\bt1\b|mprage)"):
            acquisitions["T1w"].append(item)
    return acquisitions


def choose_primary(items: list[dict], description: str) -> dict | None:
    """Select the acquisition with the most volumes and reject an unresolved tie."""
    if not items:
        return None
    largest_count = max(len(item["bvals"] or []) for item in items)
    best = [item for item in items if len(item["bvals"] or []) == largest_count]
    if len(best) != 1:
        names = ", ".join(item["prefix"] for item in best)
        raise ValueError(f"ambiguous {description} acquisitions: {names}")
    return best[0]


def source_files(item: dict, extensions: tuple[str, ...]) -> dict[str, Path]:
    helper = item["helper"]
    prefix = item["prefix"]
    sources = {extension: helper / f"{prefix}{extension}" for extension in extensions}
    missing = [path.name for path in sources.values() if not path.is_file()]
    if missing:
        raise ValueError(f"files belonging to {prefix!r} are missing: {missing}")
    return sources


def append_moves(
    moves: list[tuple[Path, Path]],
    item: dict,
    subject_dir: Path,
    datatype: str,
    basename: str,
    extensions: tuple[str, ...] = NIFTI_EXTENSIONS,
) -> None:
    for extension, source in source_files(item, extensions).items():
        moves.append((source, subject_dir / datatype / f"{basename}{extension}"))


def required_output_exists(
    session_dir: Path,
    subject_id: str,
    suffix: str,
    extensions: tuple[str, ...],
) -> bool:
    datatype = "dwi" if suffix == "dwi" else "anat"
    prefix = session_dir / datatype / f"{subject_id}_{suffix}"
    return all(Path(f"{prefix}{extension}").is_file() for extension in extensions)


def cleanup_paths(subject_dir: Path) -> list[Path]:
    candidates = (
        subject_dir / "tmp_dcm2bids",
        subject_dir / "helper",
        subject_dir / "log",
    )
    return [path for path in candidates if path.exists()]


def plan_subject(
    subject_dir: Path,
    session_label: str,
) -> tuple[list[tuple[Path, Path]], list[Path], int]:
    helper = find_helper(subject_dir)
    series = read_series(helper) if helper else []
    acquisitions = classify_series(series)
    subject_id = subject_dir.name
    session_dir = subject_dir / f"ses-{session_label}"

    # Migrate output made by the previous sessionless version of this script.
    moves: list[tuple[Path, Path]] = [
        (source, session_dir / datatype / source.relative_to(legacy_dir))
        for datatype in ("anat", "dwi", "other")
        for legacy_dir in (subject_dir / datatype,)
        if legacy_dir.is_dir()
        for source in sorted(legacy_dir.rglob("*"))
        if source.is_file()
    ]
    planned_destinations = {destination for _, destination in moves}

    def required_available(suffix: str, extensions: tuple[str, ...]) -> bool:
        datatype = "dwi" if suffix == "dwi" else "anat"
        prefix = session_dir / datatype / f"{subject_id}_{suffix}"
        expected = {Path(f"{prefix}{extension}") for extension in extensions}
        return required_output_exists(
            session_dir, subject_id, suffix, extensions
        ) or expected.issubset(planned_destinations)

    dwi = choose_primary(acquisitions["dwi"], "DWI")
    if required_available("dwi", DWI_EXTENSIONS):
        pass
    elif dwi:
        append_moves(moves, dwi, session_dir, "dwi", f"{subject_id}_dwi", DWI_EXTENSIONS)
    else:
        raise ValueError("no original diffusion acquisition with nonzero b-values found")

    t1w = choose_primary(acquisitions["T1w"], "T1w")
    if required_available("T1w", NIFTI_EXTENSIONS):
        pass
    elif t1w:
        append_moves(moves, t1w, session_dir, "anat", f"{subject_id}_T1w")
    else:
        raise ValueError("no original T1w acquisition found")

    # The reference DOC MRI dataset keeps non-T1 acquisitions under other/
    # without renaming them. Preserve every useful remaining series before the
    # temporary directory is removed, including sidecars and gradient files.
    selected_prefixes = {item["prefix"] for item in (dwi, t1w) if item}
    other_series = [
        item
        for item in series
        if item["prefix"] not in selected_prefixes and preserve_under_other(item)
    ]
    other_sources = []
    if helper:
        other_sources = sorted(
            source
            for item in other_series
            for source in helper.glob(f"{item['prefix']}.*")
            if source.is_file()
        )
    for source in other_sources:
        relative_name = source.relative_to(helper)
        moves.append((source, session_dir / "other" / relative_name))

    destinations = [destination for _, destination in moves]
    duplicates = sorted({path for path in destinations if destinations.count(path) > 1})
    if duplicates:
        raise ValueError("duplicate destinations: " + ", ".join(map(str, duplicates)))
    existing = [destination for destination in destinations if destination.exists()]
    if existing:
        raise ValueError("destination already exists: " + ", ".join(map(str, existing)))

    removals = cleanup_paths(subject_dir)
    removals.extend(
        subject_dir / datatype
        for datatype in ("anat", "dwi", "other")
        if (subject_dir / datatype).is_dir()
    )
    return moves, removals, len(other_sources)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bids_root", type=Path, help="directory containing sub-* folders")
    parser.add_argument(
        "--session-label",
        default="1",
        help="BIDS session label for converted data (default: 1)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="perform the moves and remove temporary data (otherwise print a dry run)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.bids_root.expanduser().resolve()
    if not re.fullmatch(r"[A-Za-z0-9]+", args.session_label):
        print("ERROR: --session-label must be alphanumeric", file=sys.stderr)
        return 2
    subjects = sorted(path for path in root.glob("sub-*") if path.is_dir())
    if not subjects:
        print(f"ERROR: no sub-* directories found in {root}", file=sys.stderr)
        return 1

    had_error = False
    for subject in subjects:
        try:
            moves, removals, preserved_count = plan_subject(subject, args.session_label)
            action = "ORGANIZE" if args.apply else "PLAN"
            print(f"{action} {subject.name}")
            for source, destination in moves:
                print(f"  MOVE {source} -> {destination}")
            if preserved_count:
                print(f"  PRESERVE {preserved_count} non-T1/DWI files under other/")
            for path in removals:
                print(f"  REMOVE {path}")

            if args.apply:
                for source, destination in moves:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(source, destination)
                for path in removals:
                    if path.is_dir():
                        shutil.rmtree(path)
                    else:
                        path.unlink()
        except (OSError, ValueError) as error:
            had_error = True
            print(f"SKIP {subject.name}: {error}", file=sys.stderr)

    if not args.apply:
        print("\nDry run only; rerun with --apply to organize and clean these subjects.")
    return 1 if had_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
