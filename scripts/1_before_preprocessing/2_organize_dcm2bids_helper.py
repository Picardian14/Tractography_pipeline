#!/usr/bin/env python3
"""Organize dcm2bids-helper output into the pipeline's subject/session layout.

The script processes every ``sub-*`` directory below ``bids_root``. A trailing
session number is split from the subject name: ``sub-123_2`` is organized into
``sub-123/ses-2/``, with filenames beginning ``sub-123_``. Subjects without a
session suffix use ``ses-1`` by default (or ``--session-label``). It identifies
T1w and DWI acquisitions from their dcm2niix JSON metadata and:

* gives T1w and the original diffusion series standard names in ``anat/`` and
  ``dwi/``;
* keeps b=0 acquisitions, including inverted B0, alongside DWI in ``dwi/``; and
* preserves every other imaging acquisition in ``other/`` using the same
  subject-prefixed naming pattern (for example, ``sub-123_FLAIR.nii.gz``).

This mirrors the existing DOC MRI dataset convention and keeps FLAIR, SWI, T2,
scanner-generated imaging derivatives from being discarded. Inverted B0 uses
``sub-123_acq-inverted_b0.*``; repeated acquisitions receive ``run-`` entities.
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


def subject_session(subject_dir: Path, default_session: str) -> tuple[Path, str]:
    """Interpret a trailing _<number> as the acquisition session."""
    match = re.fullmatch(r"(sub-[A-Za-z0-9]+)_([0-9]+)", subject_dir.name)
    if match:
        subject_id, session_label = match.groups()
        return subject_dir.parent / subject_id, session_label
    return subject_dir, default_session


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
        "b0": [],
        "T1w": [],
    }
    for item in series:
        if not is_original(item):
            continue

        text = item["text"]
        image_type = item["image_type"]
        bvals = item["bvals"]
        is_diffusion = "DIFFUSION" in image_type or contains(
            text, r"(?:^|[^a-z0-9])(?:diff(?:usion)?|dti)(?:[^a-z0-9]|$)"
        )
        is_b0 = contains(text, r"(?:^|[^a-z0-9])b[ _=-]?0(?:[^a-z0-9]|$)")

        # Keep b=0 references separate from the primary diffusion series:
        # they support distortion correction but contain no diffusion weighting.
        if is_diffusion and bvals and any(abs(value) > 50 for value in bvals):
            acquisitions["dwi"].append(item)
        elif (is_diffusion or is_b0) and (
            (bvals and all(abs(value) <= 50 for value in bvals))
            or (is_b0 and not bvals)
        ):
            acquisitions["b0"].append(item)
        elif contains(text, r"(?:\bt1\b|mprage)"):
            acquisitions["T1w"].append(item)
    return acquisitions


def b0_suffix(item: dict, dwi: dict | None) -> str:
    """Identify reversed phase encoding from the scan name or DWI metadata."""
    phase = item["metadata"].get("PhaseEncodingDirection")
    dwi_phase = dwi["metadata"].get("PhaseEncodingDirection") if dwi else None
    opposite_phase = (
        phase in ("i", "i-", "j", "j-", "k", "k-")
        and dwi_phase in ("i", "i-", "j", "j-", "k", "k-")
        and phase.rstrip("-") == dwi_phase.rstrip("-")
        and phase != dwi_phase
    )
    if opposite_phase or contains(
        item["text"], r"(?:^|[^a-z0-9])(?:inv(?:erted)?|rev(?:erse)?|rpe)(?:[^a-z0-9]|$)"
    ):
        return "acq-inverted_b0"
    return "b0"


def other_suffix(item: dict) -> str:
    """Use recognizable scan labels, retaining a description for unknown scans."""
    for suffix, pattern in (
        ("FLAIR", r"flair"),
        ("SWI", r"swi"),
        ("T2w", r"(?:^|[^a-z0-9])t2(?:w|[^a-z0-9]|$)"),
        ("T1w", r"(?:^|[^a-z0-9])t1(?:w|[^a-z0-9]|$)|mprage"),
        ("ADC", r"(?:^|[^a-z0-9])adc(?:[^a-z0-9]|$)"),
    ):
        if contains(item["text"], pattern):
            return suffix
    description = (
        item["metadata"].get("SeriesDescription")
        or item["metadata"].get("ProtocolName")
        or item["prefix"]
    )
    label = re.sub(r"[^A-Za-z0-9]", "", str(description)) or "unknown"
    return f"acq-{label}_image"


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
    output_subject, session_label = subject_session(subject_dir, session_label)
    subject_id = output_subject.name
    session_dir = output_subject / f"ses-{session_label}"

    # Also accept prior organized output. For suffixed input folders, move its
    # session contents into the shared subject folder and drop the old suffix
    # from filenames. Existing destinations are checked before anything moves.
    legacy_roots = [subject_dir]
    if output_subject != subject_dir:
        legacy_roots.extend(sorted(path for path in subject_dir.glob("ses-*") if path.is_dir()))
    legacy_dirs = [
        legacy_root / datatype
        for legacy_root in legacy_roots
        for datatype in ("anat", "dwi", "other")
        if (legacy_root / datatype).is_dir()
    ]
    moves: list[tuple[Path, Path]] = []
    for legacy_dir in legacy_dirs:
        for source in sorted(legacy_dir.rglob("*")):
            if not source.is_file():
                continue
            relative_path = source.relative_to(legacy_dir)
            filename = source.name
            if filename.startswith(subject_dir.name + "_"):
                filename = subject_id + filename[len(subject_dir.name) :]
            destination = session_dir / legacy_dir.name / relative_path.with_name(filename)
            moves.append((source, destination))
    planned_destinations = {destination for _, destination in moves}

    def required_available(suffix: str, extensions: tuple[str, ...]) -> bool:
        datatype = "dwi" if suffix == "dwi" else "anat"
        prefix = session_dir / datatype / f"{subject_id}_{suffix}"
        expected = {Path(f"{prefix}{extension}") for extension in extensions}
        return required_output_exists(
            session_dir, subject_id, suffix, extensions
        ) or expected.issubset(planned_destinations)

    dwi = choose_primary(acquisitions["dwi"], "DWI")
    if dwi:
        # Always plan newly supplied acquisitions. If this session already has
        # data, the destination check must reject them before helper/ is removed.
        append_moves(moves, dwi, session_dir, "dwi", f"{subject_id}_dwi", DWI_EXTENSIONS)
    elif not required_available("dwi", DWI_EXTENSIONS):
        raise ValueError("no original diffusion acquisition with nonzero b-values found")

    t1w = choose_primary(acquisitions["T1w"], "T1w")
    if t1w:
        append_moves(moves, t1w, session_dir, "anat", f"{subject_id}_T1w")
    elif not required_available("T1w", NIFTI_EXTENSIONS):
        raise ValueError("no original T1w acquisition found")

    # Preserve all companion files before deleting helper/, using one basename
    # per acquisition so NIfTI, metadata, and gradients remain paired.
    selected_prefixes = {item["prefix"] for item in (dwi, t1w) if item}
    selected_prefixes.update(item["prefix"] for item in acquisitions["b0"])
    other_series = [
        item
        for item in series
        if item["prefix"] not in selected_prefixes and preserve_under_other(item)
    ]
    groups: dict[tuple[str, str], list[dict]] = {}
    for item in acquisitions["b0"]:
        groups.setdefault(("dwi", b0_suffix(item, dwi)), []).append(item)
    for item in other_series:
        groups.setdefault(("other", other_suffix(item)), []).append(item)

    other_count = 0
    for (datatype, suffix), items in groups.items():
        for run, item in enumerate(items, start=1):
            # Repeated scans and scanner derivatives can share a modality label.
            # Number each member rather than overwriting a previous acquisition.
            entities, _, modality = suffix.rpartition("_")
            name_parts = [subject_id]
            if entities:
                name_parts.append(entities)
            if len(items) > 1:
                name_parts.append(f"run-{run}")
            basename = "_".join([*name_parts, modality])
            for source in sorted(item["helper"].iterdir()):
                if source.is_file() and source.name.startswith(item["prefix"] + "."):
                    extension = source.name[len(item["prefix"]) :]
                    moves.append((source, session_dir / datatype / f"{basename}{extension}"))
                    if datatype == "other":
                        other_count += 1

    destinations = [destination for _, destination in moves]
    duplicates = sorted({path for path in destinations if destinations.count(path) > 1})
    if duplicates:
        raise ValueError("duplicate destinations: " + ", ".join(map(str, duplicates)))
    existing = [destination for destination in destinations if destination.exists()]
    if existing:
        raise ValueError("destination already exists: " + ", ".join(map(str, existing)))

    removals = cleanup_paths(subject_dir)
    removals.extend(legacy_dirs)
    return moves, removals, other_count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bids_root", type=Path, help="directory containing sub-* folders")
    parser.add_argument(
        "--session-label",
        default="1",
        help="fallback session label for subjects without a _<number> suffix (default: 1)",
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
            output_subject, session_label = subject_session(subject, args.session_label)
            # A combined subject folder may contain only ses-2 (or other
            # sessions). It is already organized and has no default-session input.
            has_legacy_data = any((subject / datatype).is_dir() for datatype in ("anat", "dwi", "other"))
            if output_subject == subject and not find_helper(subject) and not has_legacy_data:
                if any(path.is_dir() for path in subject.glob("ses-*")):
                    print(f"ALREADY ORGANIZED {subject.name}")
                    continue
            moves, removals, preserved_count = plan_subject(subject, args.session_label)
            action = "ORGANIZE" if args.apply else "PLAN"
            print(f"{action} {subject.name} -> {output_subject.name}/ses-{session_label}")
            for source, destination in moves:
                print(f"  MOVE {source} -> {destination}")
            if preserved_count:
                print(f"  PRESERVE {preserved_count} non-T1/DWI files under other/")
            for path in removals:
                print(f"  REMOVE {path}")
            if output_subject != subject:
                print(f"  REMOVE {subject} (only if empty after organization)")

            if args.apply:
                for source, destination in moves:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(source, destination)
                for path in removals:
                    if path.is_dir():
                        shutil.rmtree(path)
                    else:
                        path.unlink()
                if output_subject != subject:
                    # Remove empty containers with rmdir so unrelated files in
                    # an old subject/session folder are never removed recursively.
                    for path in sorted(subject.glob("ses-*")):
                        if path.is_dir() and not any(path.iterdir()):
                            path.rmdir()
                    if not any(subject.iterdir()):
                        subject.rmdir()
        except (OSError, ValueError) as error:
            had_error = True
            print(f"SKIP {subject.name}: {error}", file=sys.stderr)

    if not args.apply:
        print("\nDry run only; rerun with --apply to organize and clean these subjects.")
    return 1 if had_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
