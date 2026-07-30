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
    dwiextract "${subject_id}_desc-preproc_dwi.mif" - -bzero | \
        mrmath - mean "${subject_id}_desc-mean_b0.mif" -axis 3 -force
    mrconvert "${subject_id}_desc-mean_b0.mif" "${subject_id}_desc-mean_b0.nii.gz" -force
    mrconvert "${subject_id}_desc-nocoreg_5tt.mif" "${subject_id}_desc-nocoreg_5tt.nii.gz" -force
    fslroi "${subject_id}_desc-nocoreg_5tt.nii.gz" "${subject_id}_desc-nocoreg_5tt_vol0.nii.gz" 0 1
    flirt -in "${subject_id}_desc-nocoreg_5tt_vol0.nii.gz" \
        -ref "${subject_id}_desc-mean_b0.nii.gz" \
        -interp nearestneighbour -dof 6 \
        -omat "${subject_id}_from-T1w_to-dwi_rigid.mat"
    transformconvert "${subject_id}_from-T1w_to-dwi_rigid.mat" \
        "${subject_id}_desc-nocoreg_5tt_vol0.nii.gz" \
        "${subject_id}_desc-mean_b0.nii.gz" \
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
