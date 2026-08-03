#!/bin/bash

if [ "$#" -ne 2 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/raw-dicom /absolute/path/to/output" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
folder="$(readlink -f "$1")"
mkdir -p "$2"
converted_data_dir="$(readlink -f "$2")"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
dcm2bids_job="${DCM2BIDS_JOB:-${SCRIPT_DIR}/dcm2bids_job.sh}"
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
        "$dcm2bids_job" "$file" "$subject_label"
done
