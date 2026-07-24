#!/bin/bash

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"

folder="$RAW_DICOM_DIR"
converted_data_dir="${DCM2BIDS_OUTPUT_DIR:-${BIDS_ROOT}}"
mkdir -p "$converted_data_dir"

# Iterate over each file in the folder
for file in "$folder"/*.zip; do
    [ -e "$file" ] || continue
    # Extract the filename without extension
    filename=$(basename "$file" .zip)
    
    subject_label="${filename#sub-}"

    # dcm2bids_helper creates temporary conversion data. The final dcm2bids
    # command (run with the site's configuration) must write sub-<label>/anat
    # and sub-<label>/dwi under BIDS_ROOT.
    mkdir -p "${converted_data_dir}/tmp_dcm2bids/sub-${subject_label}"
    dcm2bids_helper -d "$file" \
        -o "${converted_data_dir}/tmp_dcm2bids/sub-${subject_label}"
done
