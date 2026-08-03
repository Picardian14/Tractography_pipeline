
#!/bin/bash
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
recon_all_job="${RECON_ALL_JOB:-${SCRIPT_DIR}/recon_all_job.sh}"
mkdir -p "$output"
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [ -d "$subject_dir/anat" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="recon_all-$subject_id" \
        --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
        --output="$output/${subject_id}-recon_all-%j.out.txt" \
        --error="$output/${subject_id}-recon_all-%j.err.txt" \
        --chdir="$subject_dir/anat" \
        --mem=64G --time=24:00:00 \
        "$recon_all_job" "$subject_dir"
done
