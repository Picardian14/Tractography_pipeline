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

ml FreeSurfer/7.4.1

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
subject_dir=$1
subject_id=$(basename "$subject_dir")
t1_file=$(find "$subject_dir/anat" -maxdepth 1 -type f \
    -name "${subject_id}*_T1w.nii.gz" \
    ! -name "${subject_id}_desc-hdbet_T1w.nii.gz" \
    ! -name "${subject_id}_desc-hdbet_T1w_mask.nii.gz" \
    -print -quit)
echo "Job Doing $subject_id"
export SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-${PIPELINE_ROOT}/freesurfer7}"
mkdir -p "$SUBJECTS_DIR"
# If the subject folder in SUBJECTS_DIR does not exist, run recon-all.

echo "Running recon-all for $subject_id"
if [ ! -d "$SUBJECTS_DIR/$subject_id" ]; then
    echo "Subject folder $SUBJECTS_DIR/$subject_id does not exist. Running recon-all."
    recon-all -all -s "$subject_id" -i "$t1_file" -parallel -openmp 4
else
    echo "Subject folder $SUBJECTS_DIR/$subject_id already exists. Running without -i."
    recon-all -all -s "$subject_id" -parallel -openmp 4
    
fi
