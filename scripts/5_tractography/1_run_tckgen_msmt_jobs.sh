
#!/bin/bash
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
tckgen_job="${TCKGEN_MSMT_JOB:-${SCRIPT_DIR}/tckgen_msmt_job.sh}"
mkdir -p "$output"
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="tck-msmt-$subject_id" \
        --output="$output/${subject_id}-tck-msmt-%j.out.txt" \
        --error="$output/${subject_id}-tck-msmt-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        --mem=16G --time=12:00:00 \
        "$tckgen_job" "$subject_dir"
done
