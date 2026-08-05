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
module load singularity

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID" >&2
    exit 2
fi

if [ -z "${PIPELINE_ROOT:-}" ]; then
    if [ -n "${SLURM_JOB_ID:-}" ]; then
        echo "ERROR: PIPELINE_ROOT was not exported when this Slurm job was submitted." >&2
        exit 2
    fi
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

subject_dir=$1
subject=$(basename "$subject_dir")
dwi_bind_dir=$(readlink -f "${subject_dir}/dwi")
singularity_image="${PIPELINE_ROOT}/images/diffusion_image.sif"

echo "Job Doing $subject_dir"
echo "Current working directory: $(pwd)"
echo "Pipeline root: $PIPELINE_ROOT"

dwi_file="${subject}_desc-preproc_dwi.mif"
wm_response="${subject}_desc-meanDhollander_response-wm.txt"
gm_response="${subject}_desc-meanDhollander_response-gm.txt"
csf_response="${subject}_desc-meanDhollander_response-csf.txt"

if [ ! -f "$dwi_file" ]; then
    echo "No $dwi_file in $subject_dir/dwi" >&2
    exit 1
fi

# If the files already exist, we assume the job has already been run successfully and skip it.
if [ -f "${subject}_model-ss3t_fod-wm.mif" ] && [ -f "${subject}_model-ss3t_fod-gm.mif" ] && \
   [ -f "${subject}_model-ss3t_fod-csf.mif" ] && [ -f "${subject}_model-ss3t_vf.mif" ] && \
   [ -f "${subject}_model-ss3t_desc-normalized_fod-wm.mif" ] && \
   [ -f "${subject}_model-ss3t_desc-normalized_fod-gm.mif" ] && \
   [ -f "${subject}_model-ss3t_desc-normalized_fod-csf.mif" ]; then
    echo "All output files already exist. Skipping ss3t_csd for $subject_dir."
    exit 0
fi

if ! singularity exec \
    --bind "${dwi_bind_dir}:/dwi" \
    "$singularity_image" \
    ss3t_csd_beta1 "/dwi/${dwi_file}" \
    "/dwi/${wm_response}" "/dwi/${subject}_model-ss3t_fod-wm.mif" \
    "/dwi/${gm_response}" "/dwi/${subject}_model-ss3t_fod-gm.mif" \
    "/dwi/${csf_response}" "/dwi/${subject}_model-ss3t_fod-csf.mif" \
    -mask "/dwi/${subject}_desc-resampled_bet.mif" \
    -nthreads "${SLURM_CPUS_PER_TASK:-32}" \
    -force; then
    echo "ERROR: ss3t_csd_beta1 failed for $subject" >&2
    exit 1
fi

mrconvert -coord 3 0 "${subject}_model-ss3t_fod-wm.mif" - | \
    mrcat "${subject}_model-ss3t_fod-csf.mif" \
        "${subject}_model-ss3t_fod-gm.mif" - \
        "${subject}_model-ss3t_vf.mif" -force

mtnormalise \
    "${subject}_model-ss3t_fod-wm.mif" \
    "${subject}_model-ss3t_desc-normalized_fod-wm.mif" \
    "${subject}_model-ss3t_fod-gm.mif" \
    "${subject}_model-ss3t_desc-normalized_fod-gm.mif" \
    "${subject}_model-ss3t_fod-csf.mif" \
    "${subject}_model-ss3t_desc-normalized_fod-csf.mif" \
    -mask "${subject}_desc-resampled_bet.mif" \
    -nthreads "${SLURM_CPUS_PER_TASK:-32}" \
    -force
