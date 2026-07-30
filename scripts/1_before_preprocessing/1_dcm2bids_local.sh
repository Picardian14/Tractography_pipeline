#!/bin/bash
###############################################################################
# Run DICOM conversion locally, one ZIP file at a time.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh" $1

folder="$(readlink -f "${RAW_DICOM_DIR}")"
converted_data_dir="${DCM2BIDS_OUTPUT_DIR:-${BIDS_ROOT}}"
mkdir -p "$converted_data_dir"
converted_data_dir="$(readlink -f "$converted_data_dir")"

if [ ! -d "$folder" ]; then
    echo "DICOM directory is not accessible: $folder" >&2
    exit 1
fi

# Resolve the host paths and mount them at stable paths in the container.
singularity exec \
    --bind "${folder}:/dicom:ro" \
    --bind "${converted_data_dir}:/output" \
    "${PIPELINE_ROOT}/diffusion_image.sif" \
    bash <<'EOF'
echo "Running dcm2bids locally on all ZIP files in /dicom"

for file in /dicom/*.zip; do
    [ -e "$file" ] || continue

    filename=$(basename "$file" .zip)
    subject_label="${filename#sub-}"
    subject_output="/output/tmp_dcm2bids/sub-${subject_label}"
    mkdir -p "$subject_output"

    echo "Converting sub-${subject_label} locally"
    (
        cd "$subject_output" || exit 1
        dcm2bids_helper -d "$file" -o "$subject_output"
    )
done
EOF
