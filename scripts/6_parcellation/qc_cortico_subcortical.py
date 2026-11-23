#!/usr/bin/env python3
"""Check the combined labels and node table; anatomy still needs visual review."""

import argparse
import csv
from pathlib import Path

import nibabel as nib
import numpy as np


def check_parcellation(session, atlas, model="msmt"):
    session = Path(session).resolve()
    subject = session.parent.name
    dwi = session / "dwi"
    work = dwi / "parcellation" / atlas
    prefix = dwi / f"{subject}_atlas-{atlas}"
    with open(f"{prefix}_nodes.tsv") as stream:
        nodes = list(csv.DictReader(stream, delimiter="\t"))
    expected = np.arange(1, len(nodes) + 1)
    if [int(row["index"]) for row in nodes] != expected.tolist():
        raise ValueError("Node IDs must be consecutive and match the table order")

    def load_labels(path):
        image = nib.load(path)
        data = np.asanyarray(image.dataobj)
        if data.ndim != 3 or not np.isfinite(data).all() or (data < 0).any() or (data != np.rint(data)).any():
            raise ValueError(f"Expected a nonnegative integer 3D label image: {path}")
        return image, data.astype(np.uint32)

    def same_grid(image, reference):
        return image.shape == reference.shape and np.allclose(image.affine, reference.affine, atol=1e-4)

    native, merged = load_labels(f"{prefix}_space-T1w_parcels.nii.gz")
    reference = nib.load(session / "anat" / f"{subject}_T1w.nii.gz")
    if not same_grid(native, reference):
        raise ValueError("Combined native labels do not match the T1 grid")
    if not np.isin(merged, np.r_[0, expected]).all():
        raise ValueError("Combined atlas contains IDs absent from the node table")
    cortex_image, cortex = load_labels(work / "cortex_space-T1w.nii.gz")
    subcortex_image, subcortex = load_labels(work / "subcortex_space-T1w_nodes.nii.gz")
    if not same_grid(cortex_image, reference) or not same_grid(subcortex_image, reference):
        raise ValueError("Cortex and subcortex must occupy the same native T1 grid")
    if not np.array_equal(merged, np.where(cortex > 0, cortex, subcortex)):
        raise ValueError("Merge changed cortical labels or subcortical labels outside cortex")

    # Check source labels before conversion: labelconvert would otherwise map
    # an unrecognized subcortical ID to zero, hiding a mismatched lookup table.
    _, source_subcortex = load_labels(work / "subcortex_space-T1w_labels.nii.gz")
    known_subcortex = [int(row["source_index"]) for row in nodes if row["tissue"] == "subcortex"]
    unknown = np.setdiff1d(np.unique(source_subcortex), [0] + known_subcortex)
    if unknown.size:
        raise ValueError(f"Subcortical source labels missing from the LUT: {unknown.tolist()}")

    diffusion, dwi_labels = load_labels(f"{prefix}_space-dwi_parcels.nii.gz")
    T1_to_DWI = np.loadtxt(dwi / "rigid_T1toDWI.txt")
    # MRtrix -linear uses the inverse matrix to update scanner coordinates.
    if not np.allclose(diffusion.affine, np.linalg.inv(T1_to_DWI) @ native.affine, atol=1e-4):
        raise ValueError("Unexpected T1-to-DWI header transform")
    if not np.array_equal(merged, dwi_labels):
        raise ValueError("Header-only DWI transform changed parcel labels")

    counts = np.bincount(merged.ravel(), minlength=len(nodes) + 1)
    before_overlap = np.bincount(subcortex.ravel(), minlength=len(nodes) + 1)
    voxel_mm3 = abs(np.linalg.det(native.affine[:3, :3]))
    report = ["index\tname\ttissue\tvoxels\tvolume_mm3\tvoxels_removed_by_cortex"]
    missing = []
    for row in nodes:
        index = int(row["index"])
        removed = int(before_overlap[index] - counts[index]) if row["tissue"] == "subcortex" else 0
        report.append(f"{index}\t{row['name']}\t{row['tissue']}\t{counts[index]}\t{counts[index] * voxel_mm3:.3f}\t{removed}")
        if counts[index] == 0:
            missing.append(f"{index}:{row['name']}")
    Path(f"{prefix}_qc_volumes.tsv").write_text("\n".join(report) + "\n")

    matrix_path = dwi / f"{subject}_model-{model}_atlas-{atlas}_connectome.csv"
    matrix = np.atleast_2d(np.loadtxt(matrix_path, delimiter=","))
    if matrix.shape != (len(nodes), len(nodes)):
        raise ValueError(f"Matrix shape {matrix.shape}; expected {(len(nodes), len(nodes))}")
    if not np.isfinite(matrix).all() or (matrix < 0).any():
        raise ValueError("Connectome contains nonfinite or negative weights")
    if not np.allclose(matrix, matrix.T) or not np.allclose(np.diag(matrix), 0):
        raise ValueError("Connectome must be symmetric with a zero diagonal")
    print(f"Grids, integer IDs, cortex-priority merge and DWI transform verified; matrix: {matrix.shape}.")
    print(f"Overlap assigned to cortex: {np.count_nonzero((cortex > 0) & (subcortex > 0))} voxels.")
    print(f"Volumes: {prefix}_qc_volumes.tsv")
    if missing:
        raise ValueError("Missing atlas parcels: " + ", ".join(missing))
    print("All expected cortical and subcortical parcels are present. Inspect anatomical overlays before analysis.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path)
    parser.add_argument("atlas", help="Combined name, e.g. schaefer100-yeo7-tians2")
    parser.add_argument("--model", choices=("msmt", "ss3t"), default="msmt")
    args = parser.parse_args()
    check_parcellation(args.session, args.atlas, args.model)
