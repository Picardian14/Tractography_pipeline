#!/bin/bash

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
SUBJECTS_INPUT_DIR="${SUBJECTS_INPUT_DIR:-${BIDS_ROOT}}"

# Loop over BIDS subject folders.
for patient_folder in "$SUBJECTS_INPUT_DIR"/sub-*/; do
    [ -d "$patient_folder" ] || continue
    echo "Processing ${patient_folder} ..."
    subject_id=$(basename "$patient_folder")
    anat_dir="${patient_folder%/}/anat"
    dwi_dir="${patient_folder%/}/dwi"
    t1_file=$(find "$anat_dir" -maxdepth 1 -type f -name "${subject_id}*_T1w.nii.gz" -print -quit 2>/dev/null)

    if [ -n "$t1_file" ]; then
        mkdir -p "$dwi_dir"
        echo "Applying HD-BET to $(basename "$t1_file")"
        hd-bet -i "$t1_file" -o "$dwi_dir/preproc_mask.nii.gz" -device cpu --disable_tta
    else
        echo "No ${subject_id}*_T1w.nii.gz found in $anat_dir"
    fi
done
