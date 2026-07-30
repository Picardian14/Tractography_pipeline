#!/bin/bash

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh" $1

folder="$RAW_DICOM_DIR"
converted_data_dir="${DCM2BIDS_OUTPUT_DIR:-${BIDS_ROOT}}"
output="${OUTPUT_DIR}"
dcm2bids_job="${DCM2BIDS_JOB:-${SCRIPT_DIR}/dcm2bids_job.sh}"
mkdir -p "$converted_data_dir"
mkdir -p "$output"

for file in "$folder"/*.zip; do
    [ -e "$file" ] || continue
    filename=$(basename "$file" .zip)
    subject_label="${filename#sub-}"
    job_dir="${converted_data_dir}/tmp_dcm2bids/sub-${subject_label}"
    mkdir -p "$job_dir"
    echo "Submitting DICOM conversion for sub-${subject_label}"
    sbatch --job-name="dcm2bids-sub-${subject_label}" \
        --output="$output/sub-${subject_label}-dcm2bids-%j.out.txt" \
        --error="$output/sub-${subject_label}-dcm2bids-%j.err.txt" \
        --chdir="$job_dir" \
        "$dcm2bids_job" "$file" "$subject_label" "$PIPELINE_ROOT"
done
