#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=2

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

# Parameters to pass by command line to sbatch:
# --job-name
# --output
# --error
# --mem
# --time

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
anat_dir="$subject_dir/anat"
dwi_dir="$subject_dir/dwi"
t1_file=$(find "$anat_dir" -maxdepth 1 -type f \
    -name "${subject_id}*_T1w.nii.gz" \
    ! -name "${subject_id}_desc-hdbet_T1w.nii.gz" \
    ! -name "${subject_id}_desc-hdbet_T1w_mask.nii.gz" \
    -print -quit)
echo "Job Doing $subject_id"
echo "Current working directory: $(pwd)"

if [ ! -f "${subject_id}_desc-coreg_5tt.mif" ]; then
    echo "  - Generating 5tt coregistered to DWI..."
    mrconvert "$t1_file" "${subject_id}_T1w.mif" -force
    5ttgen fsl "${subject_id}_T1w.mif" "${subject_id}_desc-nocoreg_5tt.mif" -force        
    mrconvert "${subject_id}_desc-nocoreg_5tt.mif" "${subject_id}_desc-nocoreg_5tt.nii.gz" -force
    fslroi "${subject_id}_desc-nocoreg_5tt.nii.gz" "${subject_id}_desc-nocoreg_5tt_vol0.nii.gz" 0 1
    flirt -in "${subject_id}_desc-nocoreg_5tt_vol0.nii.gz" \
        -ref "${dwi_dir}/mean_b0_final.nii.gz" \
        -interp nearestneighbour -dof 6 \
        -omat "${subject_id}_from-T1w_to-dwi_rigid.mat"
    transformconvert "${subject_id}_from-T1w_to-dwi_rigid.mat" \
        "${subject_id}_desc-nocoreg_5tt_vol0.nii.gz" \
        "${dwi_dir}/mean_b0_final.nii.gz" \
        flirt_import "${subject_id}_from-T1w_to-dwi_rigid.txt" -force
    mrtransform "${subject_id}_desc-nocoreg_5tt.nii.gz" \
        -linear "${subject_id}_from-T1w_to-dwi_rigid.txt" -inverse \
        "${subject_id}_desc-coreg_5tt.nii.gz" -force
    mrconvert "${subject_id}_desc-coreg_5tt.nii.gz" \
        "${subject_id}_desc-coreg_5tt.mif" -force
    5tt2gmwmi "${subject_id}_desc-coreg_5tt.mif" \
        "${subject_id}_desc-coreg_gmwmi.mif" -force
else
    echo "  - ${subject_id}_desc-coreg_5tt.mif already exists, skipping generation."
fi
