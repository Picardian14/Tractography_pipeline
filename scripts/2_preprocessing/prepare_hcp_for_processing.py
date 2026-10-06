#!/usr/bin/env python3
"""Copy and prepare HCP Recommended products for the existing session pipeline."""

import argparse
import filecmp
import json
from pathlib import Path
import shutil
import subprocess

import nibabel as nib
import numpy as np


def copy_input(source, destination):
    """Keep independent copies; never overwrite a different analysis input."""
    if destination.exists() or destination.is_symlink():
        if destination.is_symlink() or not filecmp.cmp(source, destination, shallow=False):
            raise SystemExit(f"Existing input differs from its HCP source: {destination}")
    else:
        temporary = destination.with_name(destination.name + ".tmp")
        shutil.copyfile(source, temporary)
        temporary.replace(destination)


def write_json(path, metadata):
    path.write_text(json.dumps(metadata, indent=2) + "\n")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source_root", type=Path, help="Organized HCP dataset containing sourcedata/hcp")
parser.add_argument("output_root", type=Path, help="Separate, self-contained processing dataset")
parser.add_argument("--subject", help="Prepare only this subject, e.g. 100307 or sub-100307")
args = parser.parse_args()

source_root = args.source_root.resolve()
output_root = args.output_root.resolve()
hcp_root = source_root / "sourcedata/hcp"
if not hcp_root.is_dir():
    parser.error(f"Missing HCP Recommended source directory: {hcp_root}")
if source_root == output_root or source_root in output_root.parents or output_root in source_root.parents:
    parser.error("Source and output must be separate, non-overlapping datasets")
if args.subject:
    subject_label = args.subject[4:] if args.subject.startswith("sub-") else args.subject
    if not subject_label.isascii() or not subject_label.isalnum():
        parser.error(f"Invalid subject label: {args.subject}")
    subject_dirs = [hcp_root / f"sub-{subject_label}"]
    if not subject_dirs[0].is_dir():
        parser.error(f"HCP subject does not exist: {subject_dirs[0]}")
else:
    subject_dirs = sorted(path for path in hcp_root.glob("sub-*") if path.is_dir())
if not subject_dirs:
    parser.error(f"No HCP subjects found in {hcp_root}")
for command in ("mrconvert", "dwiextract", "mrmath"):
    if shutil.which(command) is None:
        parser.error(f"Required command is unavailable: {command}; load MRtrix first")

for subject_dir in subject_dirs:
    subject = subject_dir.name
    t1_dir = subject_dir / "T1w"
    anat_dir = output_root / subject / "ses-1/anat"
    dwi_dir = output_root / subject / "ses-1/dwi"
    print(f"Preparing {subject}_ses-1", flush=True)

    # Read original HCP products, independent of the organized view's filenames
    # and whether that view currently has session folders.
    sources = {
        "t1": t1_dir / "T1w_acpc_dc_restore.nii.gz",
        "brain": t1_dir / "T1w_acpc_dc_restore_brain.nii.gz",
        "t1_mask": t1_dir / "brainmask_fs.nii.gz",
        "t1_dwi": t1_dir / "T1w_acpc_dc_restore_1.25.nii.gz",
        "dwi": t1_dir / "Diffusion/data.nii.gz",
        "dwi_mask": t1_dir / "Diffusion/nodif_brain_mask.nii.gz",
        "bvals": t1_dir / "Diffusion/bvals",
        "bvecs": t1_dir / "Diffusion/bvecs",
    }
    for path in sources.values():
        if not path.is_file():
            raise SystemExit(f"Missing HCP Recommended input: {path}")
    images = {name: nib.load(sources[name]) for name in ("t1", "brain", "t1_mask", "t1_dwi", "dwi", "dwi_mask")}

    # HCP registered these diffusion products to ACPC T1w coordinates already.
    # Matching grids and the known source products support an identity mapping;
    # different anatomical/DWI voxel sizes alone do not imply a new registration.
    for reference, moving in (("dwi", "dwi_mask"), ("dwi", "t1_dwi"),
                              ("t1", "brain"), ("t1", "t1_mask")):
        a, b = images[reference], images[moving]
        if a.shape[:3] != b.shape[:3] or not np.allclose(a.affine, b.affine, atol=1e-5, rtol=0):
            raise SystemExit(f"HCP grids disagree: {reference} and {moving}")
    t1_affine, dwi_affine = images["t1"].affine, images["dwi"].affine
    t1_axes = t1_affine[:3, :3] / np.linalg.norm(t1_affine[:3, :3], axis=0)
    dwi_axes = dwi_affine[:3, :3] / np.linalg.norm(dwi_affine[:3, :3], axis=0)
    if not (np.allclose(t1_axes, dwi_axes, atol=1e-5, rtol=0) and
            np.allclose(t1_affine[:3, 3], dwi_affine[:3, 3], atol=1e-5, rtol=0)):
        raise SystemExit("HCP T1 and DWI do not have the expected common ACPC coordinates")

    dwi_shape = images["dwi"].shape
    bvals = np.loadtxt(sources["bvals"], ndmin=1)
    bvecs = np.loadtxt(sources["bvecs"], ndmin=2)
    if len(dwi_shape) != 4 or bvals.shape != (dwi_shape[3],) or bvecs.shape != (3, dwi_shape[3]):
        raise SystemExit("HCP gradient counts do not match the DWI volumes")
    if not np.isfinite(bvals).all() or not np.isfinite(bvecs).all() or not (bvals < 50).any():
        raise SystemExit("HCP gradients contain invalid values or no b=0 volumes")
    for name in ("t1_mask", "dwi_mask"):
        if not np.array_equal(np.unique(np.asarray(images[name].dataobj)), [0, 1]):
            raise SystemExit(f"Expected a nonempty binary HCP mask: {name}")
    print(f"Validated {dwi_shape[3]} volumes, gradients, binary masks, and T1/DWI geometry", flush=True)

    anat_dir.mkdir(parents=True, exist_ok=True)
    dwi_dir.mkdir(parents=True, exist_ok=True)
    destinations = {
        "t1": anat_dir / f"{subject}_T1w.nii.gz",
        "brain": anat_dir / f"{subject}_desc-brain_T1w.nii.gz",
        "t1_mask": anat_dir / f"{subject}_space-T1w_desc-brain_mask.nii.gz",
        "t1_dwi": anat_dir / f"{subject}_T1_in_dwi_space.nii.gz",
        "dwi": dwi_dir / f"{subject}_desc-preproc_dwi.nii.gz",
        "dwi_mask": dwi_dir / f"{subject}_desc-preproc_dwi_mask.nii.gz",
        "bvals": dwi_dir / f"{subject}_desc-preproc_dwi.bval",
        "bvecs": dwi_dir / f"{subject}_desc-preproc_dwi.bvec",
    }
    for name, destination in destinations.items():
        copy_input(sources[name], destination)
        if name not in ("bvals", "bvecs"):
            metadata = {"Sources": [str(sources[name])]}
            if name in ("t1", "brain", "t1_dwi"):
                metadata["SkullStripped"] = name == "brain"
            if name == "dwi":
                metadata["SpatialReference"] = f"{subject}/ses-1/anat/{subject}_T1w.nii.gz"
            write_json(destination.with_name(destination.name[:-7] + ".json"), metadata)
    grad_dev = t1_dir / "Diffusion/grad_dev.nii.gz"
    if grad_dev.is_file():
        copy_input(grad_dev, dwi_dir / f"{subject}_desc-graddev_dwi.nii.gz")

    transform = dwi_dir / "rigid_T1toDWI.txt"
    if transform.exists():
        if not np.array_equal(np.loadtxt(transform), np.eye(4)):
            raise SystemExit(f"Existing HCP transform is not identity: {transform}")
    else:
        np.savetxt(transform, np.eye(4), fmt="%.1f")
    write_json(transform.with_suffix(".json"), {
        "Sources": [str(sources["t1"]), str(sources["dwi"])],
        "CoordinateSystem": "scanner RAS millimetres",
        "Convention": "MRtrix reverse (output DWI points to input T1 points)",
        "Description": "Identity: HCP diffusion is already registered to ACPC T1w space; no new registration was estimated.",
    })

    # Temporary files are promoted only after successful commands, so an
    # interrupted conversion cannot be mistaken for a complete prepared input.
    dwi_mif = dwi_dir / f"{subject}_desc-preproc_dwi.mif"
    if not dwi_mif.is_file():
        print("Converting the supplied DWI to MRtrix format", flush=True)
        temporary = dwi_dir / "prepared_dwi.tmp.mif"
        subprocess.run(["mrconvert", str(destinations["dwi"]), str(temporary),
                        "-fslgrad", str(destinations["bvecs"]), str(destinations["bvals"]), "-force", "-quiet"], check=True)
        temporary.replace(dwi_mif)
    # The legacy filename is the common CSD input, not a claim that BET was run.
    mask_mif = dwi_dir / f"{subject}_desc-resampled_bet.mif"
    if not mask_mif.is_file():
        temporary = dwi_dir / "prepared_mask.tmp.mif"
        subprocess.run(["mrconvert", str(destinations["dwi_mask"]), str(temporary), "-datatype", "bit", "-force", "-quiet"], check=True)
        temporary.replace(mask_mif)
    mean_b0_mif = dwi_dir / "mean_b0_final.mif"
    if not mean_b0_mif.is_file():
        print("Calculating the final mean b=0", flush=True)
        b0_volumes = dwi_dir / "prepared_b0_volumes.tmp.mif"
        temporary = dwi_dir / "mean_b0_final.tmp.mif"
        subprocess.run(["dwiextract", str(dwi_mif), str(b0_volumes), "-bzero", "-force", "-quiet"], check=True)
        subprocess.run(["mrmath", str(b0_volumes), "mean", str(temporary), "-axis", "3", "-force", "-quiet"], check=True)
        temporary.replace(mean_b0_mif)
        b0_volumes.unlink()
    mean_b0_nii = dwi_dir / "mean_b0_final.nii.gz"
    if not mean_b0_nii.is_file():
        temporary = dwi_dir / "mean_b0_final.tmp.nii.gz"
        subprocess.run(["mrconvert", str(mean_b0_mif), str(temporary), "-force", "-quiet"], check=True)
        temporary.replace(mean_b0_nii)

write_json(output_root / "dataset_description.json", {
    "Name": "HCP Recommended products prepared for tractography",
    "BIDSVersion": "1.10.1",
    "DatasetType": "derivative",
    "GeneratedBy": [{"Name": "HCP minimal preprocessing pipelines"}, {"Name": "prepare_hcp_for_processing.py"}],
})
participants = sorted(path.name for path in output_root.glob("sub-*") if (path / "ses-1/dwi/mean_b0_final.nii.gz").is_file())
(output_root / "participants.tsv").write_text("participant_id\n" + "\n".join(participants) + "\n")
(output_root / "README").write_text(
    f"Source HCP dataset: {source_root}\n"
    "Inputs are independent copies of HCP Recommended products; ses-1 is the pipeline session label.\n"
    "The T1w compatibility filename contains HCP's processed high-resolution T1.\n"
    "desc-resampled_bet.mif contains HCP's supplied final diffusion-space brain mask.\n"
    "rigid_T1toDWI.txt is an identity in MRtrix physical coordinates because HCP already\n"
    "registered diffusion to ACPC T1w space. It is not an FSL matrix.\n"
    "No denoising, Synb0, eddy, brain extraction, or new registration was performed.\n"
    "Run stages 3--6 on this dataset, not the raw-DoC preprocessing launcher.\n"
)
print(f"Prepared {len(subject_dirs)} HCP session(s) in {output_root}", flush=True)
