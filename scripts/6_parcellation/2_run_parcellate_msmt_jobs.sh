
#!/bin/bash
###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh" $1
output="${OUTPUT_DIR}"
parcellate_job="${PARCELLATE_MSMT_JOB:-${SCRIPT_DIR}/parcellate_msmt_job.sh}"
data_folder="${BIDS_ROOT}"

mkdir -p "$output"
for subject_dir in "$data_folder"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="parcellate-msmt-$subject_id" \
        --output="$output/${subject_id}-parcellate-msmt-%j.out.txt" \
        --error="$output/${subject_id}-parcellate-msmt-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        --mem=32G --time=24:00:00 \
        "$parcellate_job" "$subject_dir" "$PIPELINE_ROOT"
done
