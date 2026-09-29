#!/bin/bash

set -u

BIDS_ROOT=${1:-}
if [ -z "$BIDS_ROOT" ] || [ ! -d "$BIDS_ROOT" ]; then
    echo "Usage: $0 /absolute/path/to/BIDS_data" >&2
    exit 2
fi

session_count=0
for session_dir in "$BIDS_ROOT"/sub-*/ses-*; do
    dwi_dir="$session_dir/dwi"
    [ -d "$dwi_dir" ] || continue

    subject_id=$(basename "$(dirname "$session_dir")")
    session_id=$(basename "$session_dir")
    preprocessed_dwi="$dwi_dir/${subject_id}_desc-preproc_dwi.mif"
    five_tissue="$dwi_dir/${subject_id}_desc-nocoreg_5tt.mif"

    if [ ! -f "$preprocessed_dwi" ] || [ ! -f "$five_tissue" ]; then
        echo "Skipping ${subject_id}_${session_id}: required QC images are missing." >&2
        continue
    fi

    echo "Reviewing ${subject_id}_${session_id}"
    mrview "$preprocessed_dwi" -overlay.load "$five_tissue"
    ((session_count += 1))
done

if [ "$session_count" -eq 0 ]; then
    echo "No complete session-level QC inputs found under $BIDS_ROOT." >&2
    exit 1
fi
