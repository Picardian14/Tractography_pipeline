#!/usr/bin/env python3
"""Move selected dcm2bids-helper outputs into a simple BIDS layout.

The script expects subject directories named ``sub-*``.  For each subject it:

1. identifies DWI from the unique ``.bvec`` file and its shared prefix;
2. identifies T1w from the remaining NIfTI file (preferring a name containing
   ``T1``); and
3. renames the files to ``sub-<label>_{T1w,dwi}.*`` in ``anat/`` and ``dwi/``.

Nothing is changed unless --apply is supplied.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path


DWI_EXTENSIONS = (".nii.gz", ".json", ".bval", ".bvec")
T1_EXTENSIONS = (".nii.gz", ".json")


def strip_extension(path: Path, extension: str) -> str:
    if not path.name.endswith(extension):
        raise ValueError(f"{path} does not end in {extension}")
    return path.name[: -len(extension)]


def unique_path(paths: list[Path], description: str) -> Path:
    if len(paths) != 1:
        names = ", ".join(path.name for path in paths) or "none"
        raise ValueError(f"expected one {description}, found {len(paths)}: {names}")
    return paths[0]


def find_helper(subject_dir: Path) -> Path:
    candidates = [
        subject_dir / "tmp_dcm2bids" / "helper",
        subject_dir / "helper",
    ]
    existing = [path for path in candidates if path.is_dir()]
    return unique_path(existing, "helper directory")


def plan_subject(subject_dir: Path) -> list[tuple[Path, Path]]:
    helper = find_helper(subject_dir)
    subject_id = subject_dir.name

    bvec = unique_path(list(helper.glob("*.bvec")), "DWI .bvec file")
    dwi_prefix = strip_extension(bvec, ".bvec")
    dwi_sources = {ext: helper / f"{dwi_prefix}{ext}" for ext in DWI_EXTENSIONS}
    missing = [path.name for path in dwi_sources.values() if not path.is_file()]
    if missing:
        raise ValueError(f"DWI sidecars with prefix {dwi_prefix!r} are missing: {missing}")

    other_niftis = [
        path
        for path in helper.glob("*.nii.gz")
        if path != dwi_sources[".nii.gz"]
    ]
    t1_named = [
        path for path in other_niftis if re.search(r"(^|[^a-z0-9])t1([^a-z0-9]|$)", path.name, re.I)
    ]
    t1_nii = unique_path(
        t1_named if t1_named else other_niftis,
        "T1w NIfTI file",
    )
    t1_prefix = strip_extension(t1_nii, ".nii.gz")
    t1_sources = {ext: helper / f"{t1_prefix}{ext}" for ext in T1_EXTENSIONS}
    missing = [path.name for path in t1_sources.values() if not path.is_file()]
    if missing:
        raise ValueError(f"T1w sidecars with prefix {t1_prefix!r} are missing: {missing}")

    moves: list[tuple[Path, Path]] = []
    for ext, source in t1_sources.items():
        moves.append((source, subject_dir / "anat" / f"{subject_id}_T1w{ext}"))
    for ext, source in dwi_sources.items():
        moves.append((source, subject_dir / "dwi" / f"{subject_id}_dwi{ext}"))
    return moves


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bids_root", type=Path, help="directory containing sub-* folders")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="perform the moves (without this flag, only print the plan)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.bids_root.expanduser().resolve()
    subjects = sorted(path for path in root.glob("sub-*") if path.is_dir())
    if not subjects:
        print(f"ERROR: no sub-* directories found in {root}", file=sys.stderr)
        return 1

    plans: list[tuple[Path, list[tuple[Path, Path]]]] = []
    had_error = False
    for subject in subjects:
        try:
            moves = plan_subject(subject)
            existing = [destination for _, destination in moves if destination.exists()]
            if existing:
                raise ValueError(
                    "destination already exists: " + ", ".join(str(path) for path in existing)
                )
            plans.append((subject, moves))
        except ValueError as error:
            had_error = True
            print(f"SKIP {subject.name}: {error}", file=sys.stderr)

    for subject, moves in plans:
        print(f"{'MOVE' if args.apply else 'PLAN'} {subject.name}")
        if args.apply:
            (subject / "anat").mkdir(exist_ok=True)
            (subject / "dwi").mkdir(exist_ok=True)
        for source, destination in moves:
            print(f"  {source} -> {destination}")
            if args.apply:
                shutil.move(source, destination)

    if not args.apply:
        print("\nDry run only; rerun with --apply to move these files.")
    return 1 if had_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
