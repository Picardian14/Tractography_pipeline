#!/bin/bash
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
ss3t_csd_job="${ss3t_CSD_JOB:-${SCRIPT_DIR}/ss3t_csd.sh}"

mkdir -p "$output"
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="ss3t-csd-$subject_id" \
        --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
        --output="$output/${subject_id}-ss3t-csd-%j.out.txt" \
        --error="$output/${subject_id}-ss3t-csd-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        "$ss3t_csd_job" "$subject_dir"
done
