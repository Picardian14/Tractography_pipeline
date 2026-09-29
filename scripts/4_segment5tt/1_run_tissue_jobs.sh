
#!/bin/bash
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
tissue_job="${TISSUE_JOB:-${SCRIPT_DIR}/tissue_job.sh}"
mkdir -p "$output"
for session_dir in "$BIDS_ROOT"/sub-*/ses-*; do
    [ -d "$session_dir/anat" ] && [ -d "$session_dir/dwi" ] || continue
    subject_id=$(basename "$(dirname "$session_dir")")
    session_id=$(basename "$session_dir")
    analysis_id="${subject_id}_${session_id}"
    echo "Doing $analysis_id"
    sbatch --job-name="5tt-$analysis_id" \
        --output="$output/${analysis_id}-5tt-%j.out.txt" \
        --error="$output/${analysis_id}-5tt-%j.err.txt" \
        --chdir="$session_dir/dwi" \
        --mem=16G --time=48:00:00 \
        "$tissue_job" "$session_dir"
done
