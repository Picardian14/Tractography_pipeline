#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=2

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
        "${subject_id:-$(basename "$0")}" \
        "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))" \
        "$exit_status"
}
trap report_processing_time EXIT

module load MRtrix
module load FSL
module load FreeSurfer
module load python/3.8

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID/ses-ID" >&2
    exit 2
fi

session_dir=$1
subject_id=$(basename "$(dirname "$session_dir")")
anat_dir="$session_dir/anat"
dwi_dir="$session_dir/dwi"
# DoC uses its original T1; HCP preparation supplies its high-resolution,
# bias-corrected T1 under the same compatibility filename.
t1_file="$anat_dir/${subject_id}_T1w.nii.gz"
t1_mask="$anat_dir/${subject_id}_space-T1w_desc-brain_mask.nii.gz"
echo "Job Doing $subject_id"
echo "Current working directory: $(pwd)"

if [ ! -f "${subject_id}_desc-coreg_5tt.mif" ]; then
    for required_file in "$t1_file" "$dwi_dir/rigid_T1toDWI.txt"; do
        if [ ! -f "$required_file" ]; then
            echo "Missing tissue-generation input: $required_file" >&2
            exit 1
        fi
    done
    echo "  - Generating 5tt coregistered to DWI..."
    mrconvert "$t1_file" "${subject_id}_T1w.mif" -force
    mask_options=()
    # Reuse a supplied anatomical mask. With no supplied mask, retain the
    # existing DoC segmentation behavior, including FSL brain extraction.
    if [ -f "$t1_mask" ]; then
        mask_options=(-mask "$t1_mask")
    fi
    5ttgen fsl "${subject_id}_T1w.mif" "${subject_id}_desc-nocoreg_5tt.mif" \
        "${mask_options[@]}" -force
    mrconvert "${subject_id}_desc-nocoreg_5tt.mif" "${subject_id}_desc-nocoreg_5tt.nii.gz" -force
    # Only the MRtrix transform is applied. Keep an FSL matrix for provenance
    # when available; HCP's established alignment needs no FSL matrix.
    if [ -f "${dwi_dir}/rigid_T1toDWI.mat" ]; then
        cp -f "${dwi_dir}/rigid_T1toDWI.mat" "${subject_id}_from-T1w_to-dwi_rigid.mat"
    fi
    cp -f "${dwi_dir}/rigid_T1toDWI.txt" "${subject_id}_from-T1w_to-dwi_rigid.txt"
    mrtransform "${subject_id}_desc-nocoreg_5tt.nii.gz" \
        -linear "${subject_id}_from-T1w_to-dwi_rigid.txt" \
        "${subject_id}_desc-coreg_5tt.nii.gz" -force
    mrconvert "${subject_id}_desc-coreg_5tt.nii.gz" \
        "${subject_id}_desc-coreg_5tt.mif" -force
else
    echo "  - ${subject_id}_desc-coreg_5tt.mif already exists, skipping generation."
fi
if [ ! -f "${subject_id}_desc-coreg_gmwmi.mif" ]; then
    5tt2gmwmi "${subject_id}_desc-coreg_5tt.mif" \
        "${subject_id}_desc-coreg_gmwmi.mif" -force
fi
