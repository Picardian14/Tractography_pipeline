#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL


# Atlas configurations require an annotation label and lookup-table label.

JOB_START_TIME=$SECONDS
report_processing_time() {
    local exit_status=$?
    local elapsed=$((SECONDS - JOB_START_TIME))
    printf "Processing time for %s: %02d:%02d:%02d (HH:MM:SS; exit status: %d)\n" \
        "${subject_folder:-$(basename "$0")}" \
        "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))" \
        "$exit_status"
}
trap report_processing_time EXIT

ml FreeSurfer/6.0.0
ml FSL
ml MRtrix

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
ATLAS_LABEL_NAME="${ATLAS_LABEL_NAME:-schaefer100-yeo7}" # Should indicate the folder name in the templates_parcellation folder
ATLAS_ROOT="${ATLAS_ROOT:-${PIPELINE_ROOT}/templates_parcellations}"
ATLAS_DIR="${ATLAS_DIR:-${ATLAS_ROOT}/${ATLAS_LABEL_NAME}}"
TABLE_LABEL_NAME="${TABLE_LABEL_NAME:-LUT_${ATLAS_LABEL_NAME}}" # format of Lookup tables (LUT) in the parcellation folder of the templates_parcellation
source "$FREESURFER_HOME/SetUpFreeSurfer.sh"
export SUBJECTS_DIR="${PIPELINE_ROOT}/freesurfer"


subject_dir=$1
subject_folder=$(basename "$subject_dir")
echo "Job Doing $subject_folder"
echo "Model: MSMT-CSD"
echo "Current working directory: $(pwd)"

sift_weights="${subject_folder}_model-msmt_sift2-weights.txt"
tracks="${subject_folder}_model-msmt_tractogram-10M.tck"
if [ -f "$sift_weights" ]; then

    mri_surf2surf --srcsubject fsaverage --trgsubject $subject_folder --hemi lh \
    --sval-annot $ATLAS_DIR/lh.${ATLAS_LABEL_NAME}.annot \
    --tval $SUBJECTS_DIR/$subject_folder/label/lh.${ATLAS_LABEL_NAME}.annot

    mri_surf2surf --srcsubject fsaverage --trgsubject $subject_folder --hemi rh \
    --sval-annot $ATLAS_DIR/rh.${ATLAS_LABEL_NAME}.annot \
    --tval $SUBJECTS_DIR/$subject_folder/label/rh.${ATLAS_LABEL_NAME}.annot

    mri_aparc2aseg --s $subject_folder --o $SUBJECTS_DIR/$subject_folder/mri/$ATLAS_LABEL_NAME.mgz --annot $ATLAS_LABEL_NAME

    mrconvert $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}.mgz $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}.nii.gz -force
    labelconvert $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}.nii.gz $ATLAS_DIR/$TABLE_LABEL_NAME.txt $ATLAS_DIR/${TABLE_LABEL_NAME}_OUTPUT.txt $SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}_parcels.nii.gz -force

    tck2connectome -symmetric \
        -tck_weights_in "$sift_weights" \
        "$tracks" \
        "$SUBJECTS_DIR/$subject_folder/mri/${ATLAS_LABEL_NAME}_parcels.nii.gz" \
        "${subject_folder}_model-msmt_atlas-${ATLAS_LABEL_NAME}_connectome.csv" \
        -out_assignment "${subject_folder}_model-msmt_atlas-${ATLAS_LABEL_NAME}_assignments.csv" \
        -force -zero_diagonal -nthreads "${SLURM_CPUS_PER_TASK:-4}"

else
    echo "$sift_weights not found in $subject_folder" >&2
    exit 1
fi
#bbregister --s $subject_folder --mov meanb0_post_preproc.nii --reg dwi2orig.lta --dti --init-fsl
#lta_convert --inlta dwi2orig.lta --outitk dwi2orig_itk.txt
