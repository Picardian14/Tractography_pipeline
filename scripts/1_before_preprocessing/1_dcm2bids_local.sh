#!/bin/bash
###############################################################################
# Run DICOM conversion locally, one ZIP file at a time.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
echo "Running dcm2bids locally on all ZIP files in ${RAW_DICOM_DIR}"
folder="${RAW_DICOM_DIR}"
converted_data_dir="${DCM2BIDS_OUTPUT_DIR:-${BIDS_ROOT}}"
mkdir -p "$converted_data_dir"

for file in "$folder"/*.zip; do
    [ -e "$file" ] || continue

    filename=$(basename "$file" .zip)
    subject_label="${filename#sub-}"
    subject_output="${converted_data_dir}/tmp_dcm2bids/sub-${subject_label}"
    mkdir -p "$subject_output"

    echo "Converting sub-${subject_label} locally"
    (
        cd "$subject_output" || exit 1
        dcm2bids_helper -d "$file" -o "$subject_output"
    )
done
