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

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"

subject_dir=$1
cd "$subject_dir/dwi" || exit 1

if [ ! -f "preproc_mask_resampled.mif" ]; then
    mrconvert preproc_mask.nii.gz preproc_mask.mif -force
    mrtransform preproc_mask.mif -template Diff_preproc_unbiased.mif -interp nearest preproc_mask_resampled.mif -force
fi
dwi2response dhollander Diff_preproc_unbiased.mif wm.txt gm.txt csf.txt -voxels voxels.mif -nthreads 16 -force
