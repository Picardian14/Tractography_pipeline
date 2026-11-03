#!/bin/bash
#
# Master script to preprocess subjects from a BIDS structure
# This script will:
# 1. Find all sub-*/ses-* folders in the BIDS root
# 2. Check each session for matching anat and dwi inputs
# 3. Submit one preprocessing job per session
#
# Usage: bash 1_submits_all_subs_preproc.sh /absolute/path/to/bids [synb0|reversepe]

set -eo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids [synb0|reversepe]" >&2
    exit 2
fi
SDC_METHOD="${2:-synb0}"
case "$SDC_METHOD" in
    synb0|reversepe) ;;
    *) echo "Unknown preprocessing method: $SDC_METHOD (use synb0 or reversepe)" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIDS_ROOT="$(readlink -f "$1")"
OUTPUT_DIR="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
PREPROCESS_JOB="${PREPROCESS_JOB:-${SCRIPT_DIR}/preprocess_single_subject.sh}"
mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "Submitting healthy control preprocessing jobs"
echo "BIDS dataset: $BIDS_ROOT"
echo "Distortion correction: $SDC_METHOD"
echo "=========================================="

# Counter for total jobs submitted
total_jobs=0

for session_dir in "$BIDS_ROOT"/sub-*/ses-*; do
        if [ ! -d "$session_dir" ]; then
            continue
        fi
        subject_name=$(basename "$(dirname "$session_dir")")
        session_name=$(basename "$session_dir")
        analysis_name="${subject_name}_${session_name}"
        t1_file=$(find "$session_dir/anat" -maxdepth 1 -type f \
            -name "${subject_name}*_T1w.nii.gz" \
            ! -name "${subject_name}_desc-hdbet_T1w.nii.gz" \
            ! -name "${subject_name}_desc-hdbet_T1w_mask.nii.gz" \
            -print -quit 2>/dev/null || true)
	        dwi_file=$(find "$session_dir/dwi" -maxdepth 1 -type f \
	            -name "${subject_name}*_dwi.nii.gz" \
	            ! -name "${subject_name}*_desc-preproc_dwi.nii.gz" \
	            -print -quit 2>/dev/null || true)

        if [ -n "$t1_file" ] && [ -n "$dwi_file" ]; then
            if [ "$SDC_METHOD" = reversepe ]; then
                shopt -s nullglob
                reverse_candidates=("$session_dir"/dwi/*_acq-inverted*_b0.nii.gz "$session_dir"/fmap/*_epi.nii.gz)
                shopt -u nullglob
                if [ "${#reverse_candidates[@]}" -ne 1 ] || \
                   [ ! -f "${reverse_candidates[0]%.nii.gz}.json" ]; then
                    echo "  Skipping $analysis_name: reversepe needs one dwi/*_acq-inverted*_b0.nii.gz or fmap/*_epi.nii.gz and matching JSON."
                    continue
                fi
            fi
            echo "  Submitting: $analysis_name"
            sbatch --job-name="preproc-$SDC_METHOD-$analysis_name" \
                --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
                --chdir="$session_dir/dwi" \
                --output="${OUTPUT_DIR}/${analysis_name}-preproc-${SDC_METHOD}-%j.out.txt" \
                --error="${OUTPUT_DIR}/${analysis_name}-preproc-${SDC_METHOD}-%j.err.txt" \
                "$PREPROCESS_JOB" \
                "$session_dir" "$SDC_METHOD"
            
            ((total_jobs += 1))
        fi
done

echo ""
echo "=========================================="
echo "Total jobs submitted: $total_jobs"
echo "=========================================="
echo ""
echo "Monitor jobs with: squeue -u \$USER"
echo ""
