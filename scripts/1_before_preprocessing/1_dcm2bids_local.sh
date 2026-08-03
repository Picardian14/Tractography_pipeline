#!/bin/bash
###############################################################################
# Run DICOM conversion locally, one ZIP file at a time.
###############################################################################
if [ "$#" -ne 2 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/raw-dicom /absolute/path/to/output" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
folder="$(readlink -f "$1")"
mkdir -p "$2"
converted_data_dir="$(readlink -f "$2")"

# Resolve the host paths and mount them at stable paths in the container.
singularity exec \
    --bind "${folder}:/dicom:ro" \
    --bind "${converted_data_dir}:/output" \
    "${PIPELINE_ROOT}/images/diffusion_image.sif" \
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
