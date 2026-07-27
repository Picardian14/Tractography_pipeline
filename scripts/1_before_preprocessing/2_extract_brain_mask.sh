#!/bin/bash

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
SUBJECTS_INPUT_DIR="${SUBJECTS_INPUT_DIR:-${BIDS_ROOT}}"
output="${OUTPUT_DIR}"
brain_mask_job="${BRAIN_MASK_JOB:-${SCRIPT_DIR}/extract_brain_mask_job.sh}"

mkdir -p "$output"
for patient_folder in "$SUBJECTS_INPUT_DIR"/sub-*/; do
    [ -d "$patient_folder" ] || continue
    subject_id=$(basename "$patient_folder")
    [ -d "$patient_folder/anat" ] || continue
    mkdir -p "$patient_folder/dwi"
    echo "Submitting brain-mask job for $subject_id"
    sbatch --job-name="brain-mask-$subject_id" \
        --output="$output/${subject_id}-brain-mask-%j.out.txt" \
        --error="$output/${subject_id}-brain-mask-%j.err.txt" \
        --chdir="$patient_folder/dwi" \
        "$brain_mask_job" "$patient_folder" "$PIPELINE_ROOT"
done
