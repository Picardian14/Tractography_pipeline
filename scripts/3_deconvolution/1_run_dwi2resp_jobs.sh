
#!/bin/bash
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
output="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
dwi2resp="${DWI2RESPONSE_JOB:-${SCRIPT_DIR}/dwi2response.sh}"

mkdir -p "$output"
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="dwi2resp-$subject_id" \
        --output="$output/${subject_id}-dwi2resp-%j.out.txt" \
        --error="$output/${subject_id}-dwi2resp-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        "$dwi2resp" "$subject_dir"
done
