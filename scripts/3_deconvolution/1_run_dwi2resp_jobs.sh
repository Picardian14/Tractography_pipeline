
#!/bin/bash
###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
output="${OUTPUT_DIR}"
dwi2resp="${DWI2RESPONSE_JOB:-${SCRIPT_DIR}/dwi2response.sh}"

data_folder="${BIDS_ROOT}"
mkdir -p "$output"
for subject_dir in "$data_folder"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="dwi2resp-$subject_id" \
        --output="$output/${subject_id}-dwi2resp-%j.out.txt" \
        --error="$output/${subject_id}-dwi2resp-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        "$dwi2resp" "$subject_dir" "$PIPELINE_ROOT"
done
