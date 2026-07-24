#!/bin/bash
#SBATCH --partition=medium
#SBATCH --cpus-per-task=4

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

# Parameters to pass by command line to sbatch:
# --job-name
# --output
# --error
# --mem
# --time

ml FreeSurfer/6.0.0

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"

subject_dir=$1
subject_id=$(basename "$subject_dir")
t1_file=$(find "$subject_dir/anat" -maxdepth 1 -type f -name "${subject_id}*_T1w.nii.gz" -print -quit)
echo "Job Doing $subject_id"
export SUBJECTS_DIR="${SUBJECTS_DIR:-${FREESURFER_SUBJECTS_DIR}}"
# If the subject folder in SUBJECTS_DIR does not exist, run recon-all.
if [ ! -d "$SUBJECTS_DIR/$subject_id" ]; then
    echo "Running recon-all for $subject_id"
    recon-all -all -s "$subject_id" -i "$t1_file" -parallel -openmp 4
else
    echo "Subject folder $SUBJECTS_DIR/$subject_id already exists. Skipping recon-all."
fi
