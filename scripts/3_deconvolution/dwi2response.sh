#!/bin/bash
#SBATCH --partition=medium
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --output=outputs/dwifslpreproc_all.-%j.out.txt
#SBATCH --error=outputs/dwifslpreproc_all-%j.err.txt
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

module load MRtrix
module load python/3.8
patient_folder=$1
scanner_folder=$2
data_folder=$3
cd "$data_folder"
cd "$scanner_folder"
cd "$patient_folder"        

if [ ! -f "preproc_mask_resampled.mif" ]; then
    mrconvert preproc_mask.nii.gz preproc_mask.mif -force
    mrtransform preproc_mask.mif -template Diff_preproc_unbiased.mif -interp nearest preproc_mask_resampled.mif -force
fi
dwi2response dhollander Diff_preproc_unbiased.mif wm.txt gm.txt csf.txt -voxels voxels.mif -nthreads 16 -force