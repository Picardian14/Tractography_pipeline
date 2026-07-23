#!/bin/bash
#
# Master script to preprocess subjects from the workbench structure
# This script will:
# 1. Iterate over all scanner types
# 2. Find all subjects within each scanner type
# 3. Submit preprocessing jobs for each subject/scanner combination
#
# Usage: bash preprocess_controls.sh

# Set paths
DATA_BASE="/network/iss/cohen/data/Ivan/DiffusionControl"
CODE_BASE="/network/iss/cohen/data/Ivan/Tractography/"
BASE_WORKBENCH="${DATA_BASE}/workbench"
SCRIPTS_DIR="${CODE_BASE}/scripts/"
MNI_TEMPLATE="${CODE_BASE}/MNI152_T1_2mm.nii.gz"
SYNB0_SIF="${CODE_BASE}/synb0-disco_v3.0.sif"

echo "=========================================="
echo "Submitting healthy control preprocessing jobs"
echo "Base workbench: $BASE_WORKBENCH"
echo "=========================================="

# Counter for total jobs submitted
total_jobs=0

# Iterate over scanner types
for scanner_dir in "$BASE_WORKBENCH"/workbench_*; do # THIS ASSUMES THAT SUBJECTS ARE SEPARATED IN WORKBENCH_${SCANNER_TYPE} FOLDERS
    if [ ! -d "$scanner_dir" ]; then
        continue
    fi
    # Is scanner type is siemens continue skip it
    if [ "$(basename "$scanner_dir")" == "workbench_siemens" ]; then
        continue
    fi
    
    
    scanner_type=$(basename "$scanner_dir" | sed 's/workbench_//')
    echo ""
    echo "Found scanner type: $scanner_type"
    
    # Iterate over subjects directly (no sequence layer)
    for subject_dir in "$scanner_dir"/*; do
        if [ ! -d "$subject_dir" ]; then
            continue
        fi
        
        subject_name=$(basename "$subject_dir")
        
        # Check if T1_raw and Diff_raw exist
        if [ -f "$subject_dir/T1_raw.nii.gz" ] && [ -f "$subject_dir/Diff_raw.nii.gz" ]; then
            echo "  Submitting: $subject_name (scanner: $scanner_type)"
            echo "running command: sbatch $SCRIPTS_DIR/preprocess_single_subject.sh $subject_dir $scanner_type $subject_name"
            # Submit job with subject_dir path and scanner type
            sbatch "$SCRIPTS_DIR/preprocess_single_subject.sh" \
                "$subject_dir" \
                "$scanner_type" \
                "$subject_name" \
            
            ((total_jobs++))
        fi
    done
done

echo ""
echo "=========================================="
echo "Total jobs submitted: $total_jobs"
echo "=========================================="
echo ""
echo "Monitor jobs with: squeue -u \$USER"
echo ""
