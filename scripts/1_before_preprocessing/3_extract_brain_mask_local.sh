#!/bin/bash
###############################################################################
# Run HD-BET locally, one BIDS subject at a time.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"

subjects_input_dir="${SUBJECTS_INPUT_DIR:-${BIDS_ROOT}}"

for subject_dir in "$subjects_input_dir"/sub-*; do
    [ -d "$subject_dir/anat" ] || continue

    subject=$(basename "$subject_dir")
    dwi_dir="$subject_dir/dwi"
    t1_file=$(find "$subject_dir/anat" -maxdepth 1 -type f \
        -name "${subject}*_T1w.nii.gz" -print -quit 2>/dev/null)

    if [ -z "$t1_file" ]; then
        echo "No ${subject}*_T1w.nii.gz found in $subject_dir/anat" >&2
        continue
    fi

    mkdir -p "$dwi_dir"
    echo "Applying HD-BET locally to $subject"
    (
        cd "$dwi_dir" || exit 1
        hd-bet -i "$t1_file" \
            -o "${subject}_desc-hdbet_T1w.nii.gz" \
            -device cpu --disable_tta
    )
done
