#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --output=outputs/dwifslpreproc_all.-%j.out.txt
#SBATCH --error=outputs/dwifslpreproc_all-%j.err.txt
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

JOB_START_TIME=$SECONDS
report_processing_time() {
    local exit_status=$?
    local elapsed=$((SECONDS - JOB_START_TIME))
    printf "Processing time for %s: %02d:%02d:%02d (HH:MM:SS; exit status: %d)\n" \
        "${subject:-$(basename "$0")}" \
        "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))" \
        "$exit_status"
}
trap report_processing_time EXIT

module load MRtrix
module load python/3.8

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID/ses-ID" >&2
    exit 2
fi

session_dir=$1
echo "Job Doing $session_dir"
echo "Current working directory: $(pwd)"
subject=$(basename "$(dirname "$session_dir")")

mrconvert ${subject}_desc-preproc_dwi.nii.gz ${subject}_desc-preproc_dwi.mif -fslgrad ${subject}_desc-preproc_dwi.bvec ${subject}_desc-preproc_dwi.bval -force -force 
if [ ! -f "${subject}_desc-resampled_bet.mif" ]; then
    if [ ! -f "rigid_T1toDWI.txt" ]; then
        echo "Missing T1-to-DWI transform: $(pwd)/rigid_T1toDWI.txt" >&2
        exit 1
    fi
    mrconvert "${session_dir}/anat/${subject}_desc-hdbet_T1w_bet.nii.gz" \
        "${subject}_desc-hdbet_T1w_bet.mif" -force
    mrtransform "${subject}_desc-hdbet_T1w_bet.mif" \
        -linear rigid_T1toDWI.txt \
        -template "${subject}_desc-preproc_dwi.mif" \
        -interp nearest "${subject}_desc-resampled_bet.mif" -force
fi
dwi2response dhollander "${subject}_desc-preproc_dwi.mif" \
    "${subject}_desc-dhollander_response-wm.txt" \
    "${subject}_desc-dhollander_response-gm.txt" \
    "${subject}_desc-dhollander_response-csf.txt" \
    -mask "${subject}_desc-resampled_bet.mif" \
    -voxels "${subject}_desc-dhollander_voxels.mif" \
    -nthreads 4 -force
