#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

module load singularity

PIPELINE_ROOT="$2"
source "${PIPELINE_ROOT}/scripts/paths_config.sh"

subject_dir="$1"
subject=$(basename "$subject_dir")
t1_file=$(find "$subject_dir/anat" -maxdepth 1 -type f \
    -name "${subject}*_T1w.nii.gz" \
    ! -name "${subject}_desc-hdbet_T1w.nii.gz" \
    ! -name "${subject}_desc-hdbet_T1w_mask.nii.gz" \
    -print -quit 2>/dev/null)

if [ -z "$t1_file" ]; then
    echo "No ${subject}*_T1w.nii.gz found in $subject_dir/anat" >&2
    exit 1
fi

echo "Job Doing $subject"
echo "Current working directory: $(pwd)"
bids_dir=$(readlink -f "$BIDS_ROOT")
t1_name=$(basename "$t1_file")

singularity exec \
    --bind "${bids_dir}:/bids" \
    "${PIPELINE_ROOT}/diffusion_image.sif" \
    hd-bet -i "/bids/${subject}/anat/${t1_name}" \
    -o "/bids/${subject}/anat/${subject}_desc-hdbet_T1w.nii.gz" \
    -device cpu --disable_tta
