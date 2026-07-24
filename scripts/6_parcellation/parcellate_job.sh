#!/bin/bash
#SBATCH --partition=medium
#SBATCH --cpus-per-task=4

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL


# Atlas configurations require an annotation label and lookup-table label.

ml FreeSurfer/6.0.0
ml FSL
ml MRtrix

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
export ATLAS_LABEL_NAME="${ATLAS_LABEL_NAME:-schaefer100-yeo7}"
export ATLAS_DIR="${ATLAS_DIR:-${ATLAS_ROOT}/${ATLAS_LABEL_NAME}}"
export TABLE_LABEL_NAME="${TABLE_LABEL_NAME:-LUT_${ATLAS_LABEL_NAME}}"
source $FREESURFER_HOME/SetUpFreeSurfer.sh
export SUBJECTS_DIR="${SUBJECTS_DIR:-${FREESURFER_SUBJECTS_DIR}}"


subject_dir=$1
subject_folder=$(basename "$subject_dir")
cd "$subject_dir/dwi" || exit 1
echo "Job Doing $subject_folder"


if [ -f "sift_10M_norm.txt" ]; then

    mri_surf2surf --srcsubject fsaverage --trgsubject $subject_folder --hemi lh \
    --sval-annot $ATLAS_DIR/lh.${ATLAS_LABEL_NAME}.annot \
    --tval $SUBJECTS_DIR/$subject_folder/label/lh.${ATLAS_LABEL_NAME}.annot

    mri_surf2surf --srcsubject fsaverage --trgsubject $subject_folder --hemi rh \
    --sval-annot $ATLAS_DIR/rh.${ATLAS_LABEL_NAME}.annot \
    --tval $SUBJECTS_DIR/$subject_folder/label/rh.${ATLAS_LABEL_NAME}.annot

    mri_aparc2aseg --s $subject_folder --o $SUBJECTS_DIR/$subject_folder/mri/$ATLAS_LABEL_NAME.mgz --annot $ATLAS_LABEL_NAME

    mrconvert $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}.mgz $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}.nii.gz -force
    labelconvert $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}.nii.gz $ATLAS_DIR/$TABLE_LABEL_NAME.txt $ATLAS_DIR/${TABLE_LABEL_NAME}_OUTPUT.txt $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}_parcels.nii.gz -force

    tck2connectome -symmetric -tck_weights_in sift_10M_norm.txt tracks_10M_norm.tck $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}_parcels.nii.gz SC_ss3t_${ATLAS_LABEL_NAME}.csv -out_assignment assignments_parcels_ss3t_${ATLAS_LABEL_NAME}.csv -force -zero_diagonal -nthreads 4

else
    echo "sift_10M_norm.txt not found in $subject_folder"
fi
#bbregister --s $subject_folder --mov meanb0_post_preproc.nii --reg dwi2orig.lta --dti --init-fsl
#lta_convert --inlta dwi2orig.lta --outitk dwi2orig_itk.txt
