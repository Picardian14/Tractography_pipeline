#!/bin/bash
###############################################################################
# Submit one SS3T parcellation/connectome job per BIDS subject.
###############################################################################
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
parcellate_job="${PARCELLATE_SS3T_JOB:-${SCRIPT_DIR}/parcellate_ss3t_job.sh}"

mkdir -p "$output"
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="parcellate-ss3t-$subject_id" \
        --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
        --output="$output/${subject_id}-parcellate-ss3t-%j.out.txt" \
        --error="$output/${subject_id}-parcellate-ss3t-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        --mem=32G --time=24:00:00 \
        "$parcellate_job" "$subject_dir"
done
