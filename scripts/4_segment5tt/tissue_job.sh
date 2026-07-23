#!/bin/bash
#SBATCH --partition=medium
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

patient_folder=$1
scanner_folder=$2
data_folder=$3
cd "$data_folder"
cd $scanner_folder
cd $patient_folder
echo "Job Doing $patient_folder"

#mrconvert T1_CAT12.nii T1_CAT12.mif -force
if [ ! -f "5tt_coreg.mif" ]; then
    echo "  - Generating 5tt coregistered to DWI..."
    mrconvert T1_raw.nii.gz T1_raw.mif -force
    5ttgen fsl T1_raw.mif 5tt_nocoreg.mif -force 
    dwiextract Diff_preproc_unbiased.mif - -bzero | mrmath - mean mean_b0.mif -axis 3 -force
    mrconvert mean_b0.mif mean_b0.nii.gz -force
    mrconvert 5tt_nocoreg.mif 5tt_nocoreg.nii.gz -force
    fslroi 5tt_nocoreg.nii.gz 5tt_vol0.nii.gz 0 1 
    flirt -in 5tt_vol0.nii.gz -ref mean_b0.nii.gz -interp nearestneighbour -dof 6 -omat rigid_T1toDWI.mat # suggestion by jan paul to do T1 2 Diff

    transformconvert rigid_T1toDWI.mat 5tt_vol0.nii.gz mean_b0.nii.gz flirt_import rigid_T1toDWI.txt -force # he suggested this for checking eddt unwarping step but shouldapply here as well

    mrtransform 5tt_nocoreg.nii.gz -linear rigid_T1toDWI.txt -inverse 5tt_coreg.nii -force
    mrconvert 5tt_coreg.nii 5tt_coreg.mif -force
    #mrview Diff_preproc_unbiased.mif -overlay.load 5tt_nocoreg.mif -overlay.colourmap 2 -overlay.load 5tt_coreg.mif -overlay.colourmap 1
    5tt2gmwmi 5tt_coreg.mif gmwmSeed_coreg.mif -force	

else
    echo "  - 5tt_coreg.mif already exists, skipping generation."
fi
