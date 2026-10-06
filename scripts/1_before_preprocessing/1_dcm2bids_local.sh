#!/bin/bash
###############################################################################
# Run DICOM conversion locally, one subject archive or directory at a time.
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
echo "Running dcm2bids locally on all subject ZIP archives and directories in /dicom"

shopt -s nullglob
dicom_inputs=(/dicom/*.zip /dicom/*/)
if [ "${#dicom_inputs[@]}" -eq 0 ]; then
    echo "No ZIP archives or subject directories found in /dicom" >&2
    exit 1
fi

declare -A seen_subjects
had_error=0
for file in "${dicom_inputs[@]}"; do
    input_name=$(basename "${file%/}")
    filename="${input_name%.zip}"
    subject_label="${filename#sub-}"
    if [ -n "${seen_subjects[$subject_label]+present}" ]; then
        echo "Duplicate input for sub-${subject_label}; use either its ZIP or directory" >&2
        had_error=1
        continue
    fi
    seen_subjects[$subject_label]=1

    subject_output="/output/sub-${subject_label}"
    mkdir -p "$subject_output"

    echo "Converting sub-${subject_label} locally"
    if ! (
        cd "$subject_output" || exit 1
        dcm2bids_helper -d "$file" -o "$subject_output"
    ); then
        echo "Conversion failed for sub-${subject_label}" >&2
        had_error=1
    fi
done

exit "$had_error"
EOF
