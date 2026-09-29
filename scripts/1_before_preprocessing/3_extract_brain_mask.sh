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
for session_dir in "$BIDS_ROOT"/sub-*/ses-*; do
    [ -d "$session_dir/anat" ] || continue
    subject_id=$(basename "$(dirname "$session_dir")")
    session_id=$(basename "$session_dir")
    analysis_id="${subject_id}_${session_id}"
    mkdir -p "$session_dir/dwi"
    echo "Submitting brain-mask job for $analysis_id"
    sbatch --job-name="brain-mask-$analysis_id" \
        --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
        --output="$output/${analysis_id}-brain-mask-%j.out.txt" \
        --error="$output/${analysis_id}-brain-mask-%j.err.txt" \
        --chdir="$session_dir/dwi" \
        "$brain_mask_job" "$session_dir"
done
