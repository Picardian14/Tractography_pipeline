#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

set -eo pipefail

JOB_START_TIME=$SECONDS
report_processing_time() {
    local exit_status=$?
    local elapsed=$((SECONDS - JOB_START_TIME))
    printf "Processing time for %s: %02d:%02d:%02d (HH:MM:SS; exit status: %d)\n" \
        "${fs_subject_id:-$(basename "$0")}" \
        "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))" \
        "$exit_status"
}
trap report_processing_time EXIT

ml FreeSurfer/6.0.0
ml FSL
ml MRtrix

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID/ses-ID" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
ATLAS_LABEL_NAME="${ATLAS_LABEL_NAME:-schaefer100-yeo7}"
ATLAS_ROOT="${ATLAS_ROOT:-${PIPELINE_ROOT}/templates_parcellations}"
ATLAS_DIR="${ATLAS_DIR:-${ATLAS_ROOT}/${ATLAS_LABEL_NAME}}"
TABLE_LABEL_NAME="${TABLE_LABEL_NAME:-LUT_${ATLAS_LABEL_NAME}}"
source "$FREESURFER_HOME/SetUpFreeSurfer.sh"
export SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-${PIPELINE_ROOT}/freesurfer}"

session_dir=$1
subject_folder=$(basename "$(dirname "$session_dir")")
session_id=$(basename "$session_dir")
fs_subject_id="${subject_folder}_${session_id}"
echo "Job Doing $fs_subject_id"
echo "Model: SS3T"
echo "Current working directory: $(pwd)"

sift_weights="${subject_folder}_model-ss3t_sift2-weights.txt"
tracks="${subject_folder}_model-ss3t_tractogram-10M.tck"
if [ ! -f "$sift_weights" ]; then
    echo "$sift_weights not found in $subject_folder" >&2
    exit 1
fi

# If the files already exist, we assume the job has already been run successfully and skip it.
if [ -f "${subject_folder}_model-ss3t_atlas-${ATLAS_LABEL_NAME}_connectome.csv" ] && \
   [ -f "${subject_folder}_model-ss3t_atlas-${ATLAS_LABEL_NAME}_assignments.csv" ]; then
    echo "All output files already exist. Skipping parcellation for $session_dir."
    exit 0
fi

# A dedicated trial SUBJECTS_DIR also needs FreeSurfer's atlas reference.
if [ ! -d "$SUBJECTS_DIR/fsaverage" ]; then
    if [ ! -d "$FREESURFER_HOME/subjects/fsaverage" ]; then
        echo "Cannot resolve fsaverage for $SUBJECTS_DIR" >&2
        exit 1
    fi
    # Another subject's parcellation job may create the link first.
    ln -s "$FREESURFER_HOME/subjects/fsaverage" "$SUBJECTS_DIR/fsaverage" 2>/dev/null || \
        [ -d "$SUBJECTS_DIR/fsaverage" ]
fi
t1_to_dwi="${session_dir}/dwi/rigid_T1toDWI.txt"
if [ ! -f "$tracks" ] || [ ! -f "$t1_to_dwi" ]; then
    echo "Missing tractogram or T1-to-DWI transform for $session_dir" >&2
    exit 1
fi

mri_surf2surf --srcsubject fsaverage --trgsubject "$fs_subject_id" --hemi lh \
    --sval-annot "$ATLAS_DIR/lh.${ATLAS_LABEL_NAME}.annot" \
    --tval "$SUBJECTS_DIR/$fs_subject_id/label/lh.${ATLAS_LABEL_NAME}.annot"

mri_surf2surf --srcsubject fsaverage --trgsubject "$fs_subject_id" --hemi rh \
    --sval-annot "$ATLAS_DIR/rh.${ATLAS_LABEL_NAME}.annot" \
    --tval "$SUBJECTS_DIR/$fs_subject_id/label/rh.${ATLAS_LABEL_NAME}.annot"

mri_aparc2aseg --s "$fs_subject_id" \
    --o "$SUBJECTS_DIR/$fs_subject_id/mri/$ATLAS_LABEL_NAME.mgz" \
    --annot "$ATLAS_LABEL_NAME"
mrconvert "$SUBJECTS_DIR/$fs_subject_id/mri/${ATLAS_LABEL_NAME}.mgz" \
    "$SUBJECTS_DIR/$fs_subject_id/mri/${ATLAS_LABEL_NAME}.nii.gz" -force
labelconvert \
    "$SUBJECTS_DIR/$fs_subject_id/mri/${ATLAS_LABEL_NAME}.nii.gz" \
    "$ATLAS_DIR/$TABLE_LABEL_NAME.txt" \
    "$ATLAS_DIR/${TABLE_LABEL_NAME}_OUTPUT.txt" \
    "$SUBJECTS_DIR/$fs_subject_id/mri/${ATLAS_LABEL_NAME}_parcels.nii.gz" \
    -force

# Place FreeSurfer parcels in the same physical coordinates as the tractogram.
# Without reslicing, this preserves the anatomical grid and integer labels.
parcels_dwi="${subject_folder}_atlas-${ATLAS_LABEL_NAME}_space-dwi_parcels.nii.gz"
mrtransform "$SUBJECTS_DIR/$fs_subject_id/mri/${ATLAS_LABEL_NAME}_parcels.nii.gz" \
    "$parcels_dwi" -linear "$t1_to_dwi" -force

tck2connectome -symmetric \
    -tck_weights_in "$sift_weights" \
    "$tracks" \
    "$parcels_dwi" \
    "${subject_folder}_model-ss3t_atlas-${ATLAS_LABEL_NAME}_connectome.csv" \
    -out_assignment \
    "${subject_folder}_model-ss3t_atlas-${ATLAS_LABEL_NAME}_assignments.csv" \
    -force -zero_diagonal -nthreads "${SLURM_CPUS_PER_TASK:-4}"
