#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --output=outputs/dwifslpreproc_all.-%j.out.txt
#SBATCH --error=outputs/dwifslpreproc_all-%j.err.txt
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
module load python/3.8

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID" >&2
    exit 2
fi

subject_dir=$1
echo "Job Doing $subject_dir"
echo "Current working directory: $(pwd)"
subject=$(basename "$subject_dir")

mrconvert ${subject}_desc-preproc_dwi.nii.gz ${subject}_desc-preproc_dwi.mif -fslgrad ${subject}_desc-preproc_dwi.bvec ${subject}_desc-preproc_dwi.bval -force -force 
if [ ! -f "${subject}_desc-resampled_bet.mif" ]; then
    mrconvert "${subject_dir}/anat/${subject}_desc-hdbet_T1w_bet.nii.gz" \
        "${subject}_desc-hdbet_T1w_bet.mif" -force
    mrtransform "${subject}_desc-hdbet_T1w_bet.mif" \
        -template "${subject}_desc-preproc_dwi.mif" \
        -interp nearest "${subject}_desc-resampled_bet.mif" -force
fi
#dwiextract Diff_preproc_unbiased.mif - -bzero -force | mrmath - mean meanb0_post_preproc.nii -axis 3 -force
#flirt -in T1_HDbet.nii.gz -ref meanb0_post_preproc.nii -dof 6 -omat rigid_T1toDWI.mat 			
#transformconvert rigid_T1toDWI.mat T1_HDbet.nii.gz meanb0_post_preproc.nii flirt_import rigid_T1toDWI.txt -force
#mrtransform T1_HDbet.nii.gz T1_in_dwi_space.nii.gz -linear rigid_T1toDWI.txt -force
dwi2response dhollander "${subject}_desc-preproc_dwi.mif" \
    "${subject}_desc-dhollander_response-wm.txt" \
    "${subject}_desc-dhollander_response-gm.txt" \
    "${subject}_desc-dhollander_response-csf.txt" \
    -voxels "${subject}_desc-dhollander_voxels.mif" \
    -nthreads 4 -force
