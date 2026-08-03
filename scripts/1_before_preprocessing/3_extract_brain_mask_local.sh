#!/bin/bash
###############################################################################
# Run HD-BET locally, one BIDS subject at a time.
###############################################################################
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIDS_ROOT="$(readlink -f "$1")"

# Resolve the host symlink and mount its target at a stable path in the container.
singularity exec \
    --bind "${BIDS_ROOT}:/bids" \
    "${PIPELINE_ROOT}/images/diffusion_image.sif" \
    bash <<'EOF'
for subject_dir in /bids/sub-*; do
    [ -d "$subject_dir" ] || continue

    if [ ! -d "$subject_dir/anat" ]; then
        echo "No anat directory found in $subject_dir, skipping." >&2
        continue
    fi

    subject=$(basename "$subject_dir")
    anat_dir="$subject_dir/anat"
    t1_file=$(find "$subject_dir/anat" -maxdepth 1 -type f \
        -name "${subject}*_T1w.nii.gz" \
        ! -name "${subject}_desc-hdbet_T1w.nii.gz" \
        ! -name "${subject}_desc-hdbet_T1w_mask.nii.gz" \
        -print -quit 2>/dev/null)

    if [ -z "$t1_file" ]; then
        echo "No ${subject}*_T1w.nii.gz found in $subject_dir/anat" >&2
        continue
    fi

    echo "Applying HD-BET locally to $subject"
    cd "$anat_dir" && hd-bet -i "$t1_file" \
            -o "${subject}_desc-hdbet_T1w.nii.gz" \
            -device cpu --disable_tta
done
EOF
