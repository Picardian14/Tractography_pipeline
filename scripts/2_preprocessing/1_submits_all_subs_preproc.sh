#!/bin/bash
#
# Master script to preprocess subjects from a BIDS structure
# This script will:
# 1. Find all sub-* folders in the BIDS root
# 2. Check each subject for matching anat and dwi inputs
# 3. Submit one preprocessing job per subject
#
# Usage: bash 1_submits_all_subs_preproc.sh /absolute/path/to/bids

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
OUTPUT_DIR="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
PREPROCESS_JOB="${PREPROCESS_JOB:-${SCRIPT_DIR}/preprocess_single_subject.sh}"
mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "Submitting healthy control preprocessing jobs"
echo "BIDS dataset: $BIDS_ROOT"
echo "=========================================="

# Counter for total jobs submitted
total_jobs=0

for subject_dir in "$BIDS_ROOT"/sub-*; do
        if [ ! -d "$subject_dir" ]; then
            continue
        fi
        subject_name=$(basename "$subject_dir")
        t1_file=$(find "$subject_dir/anat" -maxdepth 1 -type f \
            -name "${subject_name}*_T1w.nii.gz" \
            ! -name "${subject_name}_desc-hdbet_T1w.nii.gz" \
            ! -name "${subject_name}_desc-hdbet_T1w_mask.nii.gz" \
            -print -quit 2>/dev/null)
	        dwi_file=$(find "$subject_dir/dwi" -maxdepth 1 -type f \
	            -name "${subject_name}*_dwi.nii.gz" \
	            ! -name "${subject_name}*_desc-preproc_dwi.nii.gz" \
	            -print -quit 2>/dev/null)

        if [ -n "$t1_file" ] && [ -n "$dwi_file" ]; then
            echo "  Submitting: $subject_name"
            sbatch --job-name="preproc-$subject_name" \
                --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
                --chdir="$subject_dir/dwi" \
                --output="${OUTPUT_DIR}/${subject_name}-preproc-%j.out.txt" \
                --error="${OUTPUT_DIR}/${subject_name}-preproc-%j.err.txt" \
                "$PREPROCESS_JOB" \
                "$subject_dir"
            
            ((total_jobs++))
        fi
done

echo ""
echo "=========================================="
echo "Total jobs submitted: $total_jobs"
echo "=========================================="
echo ""
echo "Monitor jobs with: squeue -u \$USER"
echo ""
