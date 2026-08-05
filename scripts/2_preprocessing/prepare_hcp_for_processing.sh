#!/usr/bin/env bash
# Prepare organized HCP Recommended derivatives for pipeline stages 3--6.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: prepare_hcp_for_processing.sh /absolute/path/to/hcp-bids

The dataset must have been created by hcp_recommended_to_bids.sh. This script
uses the files already organized under each subject's anat/ and dwi/
directories. It creates the MRtrix DWI and mask inputs, the final mean b=0, and
the diffusion-space T1w image used for visual quality control.
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
for command_name in mrconvert dwiextract mrmath mrtransform; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command is unavailable: %s\n' "$command_name" >&2
        exit 1
    fi
done

subjects_prepared=0
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [[ -d "$subject_dir/anat" && -d "$subject_dir/dwi" ]] || continue

    subject=$(basename "$subject_dir")
    anat_dir="$subject_dir/anat"
    dwi_dir="$subject_dir/dwi"

    printf 'Preparing %s\n' "$subject"

    t1_brain="$anat_dir/${subject}_desc-hdbet_T1w.nii.gz"
    dwi_mask_nii="$dwi_dir/${subject}_desc-preproc_dwi_mask.nii.gz"

    dwi_nii="$dwi_dir/${subject}_desc-preproc_dwi.nii.gz"
    dwi_bvec="$dwi_dir/${subject}_desc-preproc_dwi.bvec"
    dwi_bval="$dwi_dir/${subject}_desc-preproc_dwi.bval"
    dwi_mif="$dwi_dir/${subject}_desc-preproc_dwi.mif"
    dwi_mask_mif="$dwi_dir/${subject}_desc-resampled_bet.mif"
    mean_b0_mif="$dwi_dir/mean_b0_final.mif"
    mean_b0_nii="$dwi_dir/mean_b0_final.nii.gz"
    t1_in_dwi="$anat_dir/${subject}_T1_in_dwi_space.nii.gz"

    for required_file in \
        "$dwi_nii" "$dwi_bvec" "$dwi_bval" "$dwi_mask_nii" \
        "$t1_brain"; do
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
    mv "$dwi_mask_mif" "$dwi_dir/${subject}_desc-preproc_b0_mask.mif"
    if [[ ! -f "$mean_b0_mif" ]]; then
        dwiextract "$dwi_mif" - -bzero | \
            mrmath - mean "$mean_b0_mif" -axis 3
    fi
    if [[ ! -f "$mean_b0_nii" ]]; then
        mrconvert "$mean_b0_mif" "$mean_b0_nii"
    fi

    mv "${anat_dir}/${subject}_desc-hdbet_T1w.nii.gz" "$t1_in_dwi"

    mv ${anat_dir}/${subject}_desc-preproc_T1w.nii.gz ${anat_dir}/${subject}_T1w.nii.gz
    mv ${anat_dir}/${subject}_desc-preproc_T1w.json ${anat_dir}/${subject}_T1w.json

    subjects_prepared=$((subjects_prepared + 1))
done

if [[ $subjects_prepared -eq 0 ]]; then
    printf 'No HCP subjects were prepared under %s\n' "$BIDS_ROOT" >&2
    exit 1
fi

printf 'Prepared %d HCP subject(s) for pipeline stages 3--6.\n' "$subjects_prepared"
