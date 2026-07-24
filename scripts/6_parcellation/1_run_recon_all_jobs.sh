
#!/bin/bash
###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
output="${OUTPUT_DIR}"
recon_all_job="${RECON_ALL_JOB:-${SCRIPT_DIR}/recon_all_job.sh}"
data_folder="${BIDS_ROOT}"
mkdir -p "$output"
for subject_dir in "$data_folder"/sub-*; do
    [ -d "$subject_dir/anat" ] || continue
    subject_id=$(basename "$subject_dir")
    echo "Doing $subject_id"
    sbatch --job-name="recon_all-$subject_id" \
        --output="$output/${subject_id}-recon_all-%j.out.txt" \
        --error="$output/${subject_id}-recon_all-%j.err.txt" \
        --mem=64G --time=24:00:00 "$recon_all_job" "$subject_dir"
done
