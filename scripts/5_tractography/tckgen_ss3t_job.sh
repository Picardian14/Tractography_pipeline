#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=8
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

JOB_START_TIME=$SECONDS
report_processing_time() {
    local exit_status=$?
    local elapsed=$((SECONDS - JOB_START_TIME))
    printf "Processing time for %s: %02d:%02d:%02d (HH:MM:SS; exit status: %d)\n" \
        "${subject_id:-$(basename "$0")}" \
        "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))" \
        "$exit_status"
}
trap report_processing_time EXIT

module load MRtrix
module load FSL
module load FreeSurfer
module load python/3.8

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID" >&2
    exit 2
fi

subject_dir=$1
subject_id=$(basename "$subject_dir")
echo "Job Doing $subject_id"
echo "Model: SS3T"
echo "Current working directory: $(pwd)"

wm_fod="${subject_id}_model-ss3t_desc-normalized_fod-wm.mif"
act_file="${subject_id}_desc-coreg_5tt.mif"
seed_file="${subject_id}_desc-coreg_gmwmi.mif"
tracks="${subject_id}_model-ss3t_tractogram-10M.tck"

if [ ! -f "$wm_fod" ]; then
    echo "$wm_fod not found in $subject_dir/dwi" >&2
    exit 1
fi

tckgen -act "$act_file" -backtrack -seed_gmwmi "$seed_file" \
    -nthreads "${SLURM_CPUS_PER_TASK:-8}" -select 10000000 \
    "$wm_fod" "$tracks" -force
tckedit "$tracks" -number 200k \
    "${subject_id}_model-ss3t_tractogram-200k.tck" -force
tcksift2 -act "$act_file" \
    -out_mu "${subject_id}_model-ss3t_sift2-mu.txt" \
    -out_coeffs "${subject_id}_model-ss3t_sift2-coeffs.txt" \
    -nthreads "${SLURM_CPUS_PER_TASK:-8}" \
    "$tracks" "$wm_fod" "${subject_id}_model-ss3t_sift2-weights.txt" -force
