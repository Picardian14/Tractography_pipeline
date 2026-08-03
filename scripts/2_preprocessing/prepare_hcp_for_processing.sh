#!/usr/bin/env bash
# Prepare HCP Recommended derivatives for stages 3--6 of this pipeline.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: prepare_hcp_for_processing.sh /absolute/path/to/hcp-bids

The dataset must have been created by hcp_recommended_to_bids.sh and retain the
complete HCP subjects under sourcedata/hcp/sub-<label>.  This script reuses the
HCP anatomical and diffusion masks, creates MRtrix inputs, and produces the
T1-to-DWI registration files used for visual quality control.
EOF
}

if [[ $# -ne 1 || ! -d "$1" ]]; then
    usage >&2
    exit 2
fi

BIDS_ROOT=$(readlink -f "$1")

if ! command -v mrconvert >/dev/null 2>&1; then
    type module >/dev/null 2>&1 && module load MRtrix
fi
if ! command -v flirt >/dev/null 2>&1; then
    type module >/dev/null 2>&1 && module load FSL
fi
for command_name in mrconvert dwiextract mrmath transformconvert flirt; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command is unavailable: %s\n' "$command_name" >&2
        exit 1
    fi
done

link_input() {
    local source=$1
    local destination=$2

    if [[ ! -f "$source" ]]; then
        printf 'Required HCP file is missing: %s\n' "$source" >&2
        return 1
    fi
    if [[ -e "$destination" ]]; then
        if [[ "$source" -ef "$destination" ]]; then
            return 0
        fi
        printf 'Refusing to replace existing file: %s\n' "$destination" >&2
        return 1
    fi
    ln "$source" "$destination"
}

subjects_prepared=0
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [[ -d "$subject_dir/anat" && -d "$subject_dir/dwi" ]] || continue

    subject=$(basename "$subject_dir")
    hcp_subject="$BIDS_ROOT/sourcedata/hcp/$subject"
    hcp_t1w="$hcp_subject/T1w"
    hcp_diffusion="$hcp_t1w/Diffusion"
    anat_dir="$subject_dir/anat"
    dwi_dir="$subject_dir/dwi"

    if [[ ! -d "$hcp_diffusion" ]]; then
        printf 'Skipping %s: HCP sourcedata directory is missing: %s\n' \
            "$subject" "$hcp_diffusion" >&2
        continue
    fi

    printf 'Preparing %s\n' "$subject"

    t1_brain="$anat_dir/${subject}_desc-hdbet_T1w.nii.gz"
    t1_mask="$anat_dir/${subject}_desc-hdbet_T1w_bet.nii.gz"
    t1_dwi_resolution="$anat_dir/${subject}_space-dwi_desc-preproc_T1w.nii.gz"
    dwi_mask_nii="$dwi_dir/${subject}_desc-preproc_dwi_mask.nii.gz"
    graddev="$dwi_dir/${subject}_desc-graddev_dwi.nii.gz"

    link_input "$hcp_t1w/T1w_acpc_dc_restore_brain.nii.gz" "$t1_brain"
    link_input "$hcp_t1w/brainmask_fs.nii.gz" "$t1_mask"
    link_input "$hcp_t1w/T1w_acpc_dc_restore_1.25.nii.gz" "$t1_dwi_resolution"
    link_input "$hcp_diffusion/nodif_brain_mask.nii.gz" "$dwi_mask_nii"
    if [[ -f "$hcp_diffusion/grad_dev.nii.gz" && ! -e "$graddev" ]]; then
        ln "$hcp_diffusion/grad_dev.nii.gz" "$graddev"
    fi
    if [[ -f "$hcp_diffusion/eddy_parameters" ]]; then
        eddy_parameters="$dwi_dir/${subject}_desc-eddy_parameters.txt"
        if [[ ! -e "$eddy_parameters" ]]; then
            ln "$hcp_diffusion/eddy_parameters" "$eddy_parameters"
        fi
    fi

    dwi_nii="$dwi_dir/${subject}_desc-preproc_dwi.nii.gz"
    dwi_bvec="$dwi_dir/${subject}_desc-preproc_dwi.bvec"
    dwi_bval="$dwi_dir/${subject}_desc-preproc_dwi.bval"
    dwi_mif="$dwi_dir/${subject}_desc-preproc_dwi.mif"
    dwi_mask_mif="$dwi_dir/${subject}_desc-resampled_mask.mif"
    mean_b0_mif="$dwi_dir/mean_b0_final.mif"
    mean_b0_nii="$dwi_dir/mean_b0_final.nii.gz"

    for required_file in "$dwi_nii" "$dwi_bvec" "$dwi_bval"; do
        if [[ ! -f "$required_file" ]]; then
            printf 'Required organized HCP input is missing: %s\n' "$required_file" >&2
            exit 1
        fi
    done

    if [[ ! -f "$dwi_mif" ]]; then
        mrconvert "$dwi_nii" "$dwi_mif" \
            -fslgrad "$dwi_bvec" "$dwi_bval"
    fi
    if [[ ! -f "$dwi_mask_mif" ]]; then
        mrconvert "$dwi_mask_nii" "$dwi_mask_mif" \
            -datatype bit
    fi
    if [[ ! -f "$mean_b0_mif" ]]; then
        dwiextract "$dwi_mif" - -bzero | \
            mrmath - mean "$mean_b0_mif" -axis 3
    fi
    if [[ ! -f "$mean_b0_nii" ]]; then
        mrconvert "$mean_b0_mif" "$mean_b0_nii"
    fi

    rigid_fsl="$dwi_dir/rigid_T1toDWI.mat"
    rigid_mrtrix="$dwi_dir/rigid_T1toDWI.txt"
    t1_in_dwi="$anat_dir/${subject}_T1_in_dwi_space.nii.gz"
    if [[ ! -f "$rigid_fsl" || ! -f "$t1_in_dwi" ]]; then
        flirt -in "$t1_brain" -ref "$mean_b0_nii" \
            -out "$t1_in_dwi" -omat "$rigid_fsl" \
            -dof 6 -cost mutualinfo
    fi
    if [[ ! -f "$rigid_mrtrix" ]]; then
        transformconvert "$rigid_fsl" "$t1_brain" "$mean_b0_nii" \
            flirt_import "$rigid_mrtrix"
    fi

    subjects_prepared=$((subjects_prepared + 1))
done

if [[ $subjects_prepared -eq 0 ]]; then
    printf 'No HCP subjects were prepared under %s\n' "$BIDS_ROOT" >&2
    exit 1
fi

printf 'Prepared %d HCP subject(s) for pipeline stages 3--6.\n' "$subjects_prepared"
