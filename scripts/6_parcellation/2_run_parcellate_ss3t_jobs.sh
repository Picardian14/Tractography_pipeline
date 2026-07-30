#!/bin/bash
###############################################################################
# Submit one SS3T parcellation/connectome job per BIDS subject.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh" $1
output="${OUTPUT_DIR}"
parcellate_job="${PARCELLATE_SS3T_JOB:-${SCRIPT_DIR}/parcellate_ss3t_job.sh}"
data_folder="${BIDS_ROOT}"

mkdir -p "$output"
for subject_dir in "$data_folder"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="parcellate-ss3t-$subject_id" \
        --output="$output/${subject_id}-parcellate-ss3t-%j.out.txt" \
        --error="$output/${subject_id}-parcellate-ss3t-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        --mem=32G --time=24:00:00 \
        "$parcellate_job" "$subject_dir" "$PIPELINE_ROOT"
done
