#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

# Parameters to pass by command line to sbatch:
# --job-name
# --output
# --error
# --mem
# --time

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

ml FreeSurfer/6.0.0 # FreeSurfer has to be either installed or loaded as a module
ml singularity

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID/ses-ID" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
FREESURFER_SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-${PIPELINE_ROOT}/freesurfer}" # SOFT LINK THE PATH YOU WILL LIKE TO HAVE YOUR FREESURFER SUBJECTS DIR TO, OR CHANGE THIS VARIABLE TO AN EXISTING FREESURFER SUBJECTS DIR

session_dir=$1
subject_id=$(basename "$(dirname "$session_dir")")
session_id=$(basename "$session_dir")
fs_subject_id="${subject_id}_${session_id}"
t1_file="$session_dir/anat/${subject_id}_T1w.nii.gz"
echo "Job Doing $fs_subject_id"
export SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR}"
# If the subject folder in SUBJECTS_DIR does not exist, run recon-all.

echo "Running recon-all for $fs_subject_id"
# Use the same repository-owned Singularity image as HD-BET.
SINGULARITY_IMAGE="${PIPELINE_ROOT}/images/diffusion_image.sif"
# Bind necessary paths so recon-all inside the container can access data and FREESURFER subjects dir
ANAT_DIR="${session_dir}/anat"
ANAT_BIND_DIR=$(readlink -f "$ANAT_DIR")
FREESURFER_BIND_DIR=$(readlink -f "${FREESURFER_SUBJECTS_DIR}") # You have to bind the freesurfer folder
BIND_PATHS=("${FREESURFER_SUBJECTS_DIR}:${FREESURFER_SUBJECTS_DIR}" "${session_dir}:${session_dir}" "${PIPELINE_ROOT}:${PIPELINE_ROOT}" "${HOME}:${HOME}" "${ANAT_BIND_DIR}:/anat" "${FREESURFER_BIND_DIR}:/subjects" "$FREESURFER_HOME/license.txt:/usr/local/freesurfer/license.txt")
bind_arg=$(IFS=, ; echo "${BIND_PATHS[*]}")

run_recon_cmd() {
    if [ -f "$SINGULARITY_IMAGE" ]; then
        singularity exec --bind "$bind_arg" "$SINGULARITY_IMAGE" \
            recon-all "$@"
    else
        echo "Singularity image $SINGULARITY_IMAGE not found." >&2
        return 1
    fi
}

# If the relevant surface files already exist, we assume the job has already been run successfully and skip it.
if [ -f "${SUBJECTS_DIR}/${fs_subject_id}/surf/lh.white" ] && [ -f "${SUBJECTS_DIR}/${fs_subject_id}/surf/rh.white" ] && [ -f "${SUBJECTS_DIR}/${fs_subject_id}/surf/lh.pial" ] && [ -f "${SUBJECTS_DIR}/${fs_subject_id}/surf/rh.pial" ]; then
    echo "All output files already exist. Skipping recon-all for $session_dir."
    exit 0
fi

if [ ! -d "$SUBJECTS_DIR/$fs_subject_id" ]; then
    if [ ! -f "$t1_file" ]; then
        echo "Missing anatomical input: $t1_file" >&2
        exit 1
    fi
    echo "Subject folder $SUBJECTS_DIR/$fs_subject_id does not exist. Running recon-all with -i."
    run_recon_cmd -all -s "$fs_subject_id" \
    -i "/anat/$(basename "$t1_file")" \
    -parallel -openmp 4
else
    echo "Subject folder $SUBJECTS_DIR/$fs_subject_id already exists. Running without -i."
    run_recon_cmd -all -s "$fs_subject_id" -parallel -openmp 4
fi
