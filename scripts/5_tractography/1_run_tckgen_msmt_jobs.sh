
#!/bin/bash
###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
output="${OUTPUT_DIR}"
tckgen_job="${TCKGEN_MSMT_JOB:-${SCRIPT_DIR}/tckgen_msmt_job.sh}"
data_folder="${BIDS_ROOT}"
mkdir -p "$output"
for subject_dir in "$data_folder"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="tck-msmt-$subject_id" \
        --output="$output/${subject_id}-tck-msmt-%j.out.txt" \
        --error="$output/${subject_id}-tck-msmt-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        --mem=16G --time=12:00:00 \
        "$tckgen_job" "$subject_dir" "$PIPELINE_ROOT"
done
