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

shopt -s nullglob
dicom_inputs=("$folder"/*.zip "$folder"/*/)
if [ "${#dicom_inputs[@]}" -eq 0 ]; then
    echo "No ZIP archives or subject directories found in $folder" >&2
    exit 1
fi

declare -A seen_subjects
had_error=0
for file in "${dicom_inputs[@]}"; do
    input_name=$(basename "${file%/}")
    filename="${input_name%.zip}"
    subject_label="${filename#sub-}"
    if [ -n "${seen_subjects[$subject_label]+present}" ]; then
        echo "Duplicate input for sub-${subject_label}; use either its ZIP or directory" >&2
        had_error=1
        continue
    fi
    seen_subjects[$subject_label]=1

    job_dir="${converted_data_dir}/tmp_dcm2bids/sub-${subject_label}"
    mkdir -p "$job_dir"
    echo "Submitting DICOM conversion for sub-${subject_label}"
    if ! sbatch --job-name="dcm2bids-sub-${subject_label}" \
            --output="$output/sub-${subject_label}-dcm2bids-%j.out.txt" \
            --error="$output/sub-${subject_label}-dcm2bids-%j.err.txt" \
            --chdir="$job_dir" \
            "$dcm2bids_job" "$file" "$subject_label"; then
        echo "Failed to submit conversion for sub-${subject_label}" >&2
        had_error=1
    fi
done

exit "$had_error"
