#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=32
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

JOB_START_TIME=$SECONDS
report_processing_time() {
    local exit_status=$?
    local elapsed=$((SECONDS - JOB_START_TIME))
    printf "Processing time for %s: %02d:%02d:%02d (HH:MM:SS; exit status: %d)\n" \
        "${subject:-$(basename "$0")}" \
        "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))" \
        "$exit_status"
}
trap report_processing_time EXIT

module load MRtrix

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID" >&2
    exit 2
fi

subject_dir=$1
subject=$(basename "$subject_dir")

echo "Job Doing $subject_dir"
echo "Current working directory: $(pwd)"

dwi_file="${subject}_desc-preproc_dwi.mif"
wm_response="${subject}_desc-meanDhollander_response-wm.txt"
gm_response="${subject}_desc-meanDhollander_response-gm.txt"
csf_response="${subject}_desc-meanDhollander_response-csf.txt"

if [ ! -f "$dwi_file" ]; then
    echo "No $dwi_file in $subject_dir/dwi" >&2
    exit 1
fi

# If the files already exist, we assume the job has already been run successfully and skip it.
if [ -f "${subject}_model-msmt_fod-wm.mif" ] && [ -f "${subject}_model-msmt_fod-gm.mif" ] && \
   [ -f "${subject}_model-msmt_fod-csf.mif" ] && [ -f "${subject}_model-msmt_vf.mif" ] && \
   [ -f "${subject}_model-msmt_desc-normalized_fod-wm.mif" ] && \
   [ -f "${subject}_model-msmt_desc-normalized_fod-gm.mif" ] && \
   [ -f "${subject}_model-msmt_desc-normalized_fod-csf.mif" ]; then
    echo "All output files already exist. Skipping msmt_csd for $subject_dir."
    exit 0
fi

dwi2fod msmt_csd "$dwi_file" \
    "$wm_response" "${subject}_model-msmt_fod-wm.mif" \
    "$gm_response" "${subject}_model-msmt_fod-gm.mif" \
    "$csf_response" "${subject}_model-msmt_fod-csf.mif" \
    -mask "${subject}_desc-resampled_bet.mif" \
    -nthreads "${SLURM_CPUS_PER_TASK:-32}" \
    -force

mrconvert -coord 3 0 "${subject}_model-msmt_fod-wm.mif" - | \
    mrcat "${subject}_model-msmt_fod-csf.mif" \
        "${subject}_model-msmt_fod-gm.mif" - \
        "${subject}_model-msmt_vf.mif" -force

mtnormalise \
    "${subject}_model-msmt_fod-wm.mif" \
    "${subject}_model-msmt_desc-normalized_fod-wm.mif" \
    "${subject}_model-msmt_fod-gm.mif" \
    "${subject}_model-msmt_desc-normalized_fod-gm.mif" \
    "${subject}_model-msmt_fod-csf.mif" \
    "${subject}_model-msmt_desc-normalized_fod-csf.mif" \
    -mask "${subject}_desc-resampled_bet.mif" \
    -nthreads "${SLURM_CPUS_PER_TASK:-32}" \
    -force
