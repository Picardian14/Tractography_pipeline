#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --output=outputs/dwifslpreproc_all.-%j.out.txt
#SBATCH --error=outputs/dwifslpreproc_all-%j.err.txt
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

module load MRtrix
module load python/3.8

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
#SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#source "${SCRIPT_DIR}/../paths_config.sh"
PIPELINE_ROOT=$2
source "${PIPELINE_ROOT}/scripts/paths_config.sh"

subject_dir=$1
echo "Job Doing $subject_dir"
echo "Current working directory: $(pwd)"
subject=$(basename "$subject_dir")

mrconvert ${subject}_desc-preproc_dwi.nii.gz ${subject}_desc-preproc_dwi.mif -fslgrad ${subject}_desc-preproc_dwi.bvec ${subject}_desc-preproc_dwi.bval -force -force 
if [ ! -f "${subject}_desc-resampled_mask.mif" ]; then
    mrconvert "${subject_dir}/anat/${subject}_desc-hdbet_T1w_mask.nii.gz" \
        "${subject}_desc-hdbet_T1w_mask.mif" -force
    mrtransform "${subject}_desc-hdbet_T1w_mask.mif" \
        -template "${subject}_desc-preproc_dwi.mif" \
        -interp nearest "${subject}_desc-resampled_mask.mif" -force
fi
dwi2response dhollander "${subject}_desc-preproc_dwi.mif" \
    "${subject}_desc-dhollander_response-wm.txt" \
    "${subject}_desc-dhollander_response-gm.txt" \
    "${subject}_desc-dhollander_response-csf.txt" \
    -voxels "${subject}_desc-dhollander_voxels.mif" \
    -nthreads 16 -force
