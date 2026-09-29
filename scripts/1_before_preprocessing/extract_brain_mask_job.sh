#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

module load singularity

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID/ses-ID" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

session_dir="$1"
subject=$(basename "$(dirname "$session_dir")")
session=$(basename "$session_dir")
t1_file=$(find "$session_dir/anat" -maxdepth 1 -type f \
    -name "${subject}*_T1w.nii.gz" \
    ! -name "${subject}_desc-hdbet_T1w.nii.gz" \
    ! -name "${subject}_desc-hdbet_T1w_bet.nii.gz" \
    -print -quit 2>/dev/null)

if [ -z "$t1_file" ]; then
    echo "No ${subject}*_T1w.nii.gz found in $session_dir/anat" >&2
    exit 1
fi

echo "Job Doing ${subject}_${session}"
echo "Current working directory: $(pwd)"
subject_bind_dir=$(readlink -f "$session_dir")
t1_name=$(basename "$t1_file")

singularity exec \
    --bind "${subject_bind_dir}:/subject" \
    "${PIPELINE_ROOT}/images/diffusion_image.sif" \
    hd-bet -i "/subject/anat/${t1_name}" \
    -o "/subject/anat/${subject}_desc-hdbet_T1w.nii.gz" \
    -device cpu --disable_tta --save_bet_mask
