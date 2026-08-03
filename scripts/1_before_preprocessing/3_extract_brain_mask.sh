#!/bin/bash

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
brain_mask_job="${BRAIN_MASK_JOB:-${SCRIPT_DIR}/extract_brain_mask_job.sh}"

mkdir -p "$output"
for patient_folder in "$BIDS_ROOT"/sub-*/; do
    [ -d "$patient_folder" ] || continue
    subject_id=$(basename "$patient_folder")
    [ -d "$patient_folder/anat" ] || continue
    mkdir -p "$patient_folder/dwi"
    echo "Submitting brain-mask job for $subject_id"
    sbatch --job-name="brain-mask-$subject_id" \
        --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
        --output="$output/${subject_id}-brain-mask-%j.out.txt" \
        --error="$output/${subject_id}-brain-mask-%j.err.txt" \
        --chdir="$patient_folder/dwi" \
        "$brain_mask_job" "$patient_folder"
done
