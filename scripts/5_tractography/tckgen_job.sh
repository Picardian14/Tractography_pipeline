#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=8

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

# Parameters to pass by command line to sbatch:
# --job-name
# --output
# --error
# --mem
# --time

module load MRtrix
module load FSL
module load FreeSurfer
module load python/3.8

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
PIPELINE_ROOT=$2
source "${PIPELINE_ROOT}/scripts/paths_config.sh"

subject_dir=$1
subject_id=$(basename "$subject_dir")
echo "Job Doing $subject_id"
echo "Current working directory: $(pwd)"

wm_fod="${subject_id}_model-msmt_desc-normalized_fod-wm.mif"
act_file="${subject_id}_desc-coreg_5tt.mif"
seed_file="${subject_id}_desc-coreg_gmwmi.mif"
tracks="${subject_id}_model-msmt_tractogram-10M.tck"

if [ -f "$wm_fod" ]; then
    tckgen -act "$act_file" -backtrack -seed_gmwmi "$seed_file" \
        -nthreads "${SLURM_CPUS_PER_TASK:-8}" -select 10000000 \
        "$wm_fod" "$tracks" -force
    tckedit "$tracks" -number 200k \
        "${subject_id}_model-msmt_tractogram-200k.tck" -force
    tcksift2 -act "$act_file" \
        -out_mu "${subject_id}_model-msmt_sift2-mu.txt" \
        -out_coeffs "${subject_id}_model-msmt_sift2-coeffs.txt" \
        -nthreads "${SLURM_CPUS_PER_TASK:-8}" \
        "$tracks" "$wm_fod" "${subject_id}_model-msmt_sift2-weights.txt" -force
else
    echo "$wm_fod not found in $subject_dir/dwi" >&2
    exit 1
fi
