#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=32
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

module load MRtrix

PIPELINE_ROOT=$2
source "${PIPELINE_ROOT}/scripts/paths_config.sh"

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

dwi2fod msmt_csd "$dwi_file" \
    "$wm_response" "${subject}_model-msmt_fod-wm.mif" \
    "$gm_response" "${subject}_model-msmt_fod-gm.mif" \
    "$csf_response" "${subject}_model-msmt_fod-csf.mif" \
    -mask preproc_mask_resampled.mif \
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
    -mask preproc_mask_resampled.mif \
    -nthreads "${SLURM_CPUS_PER_TASK:-32}" \
    -force
