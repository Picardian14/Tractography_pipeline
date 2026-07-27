#!/bin/bash
###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${1:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
source "${PIPELINE_ROOT}/scripts/paths_config.sh"
BIDS_DATASET="${BIDS_DATASET:-${BIDS_ROOT}}"
cd "$BIDS_DATASET" || exit 1
for subject_dir in sub-*/; do
        [ -d "$subject_dir/dwi" ] || continue
        echo "Doing $subject_dir"
		subject=$(basename "$subject_dir")
		cd "$subject_dir/dwi" || continue
            if [ -f "${subject}_desc-preproc_dwi.nii.gz" ]; then
				if [ -f "${subject}_desc-preproc_dwi.mif" ]; then
					dwi2fod msmt_csd "${subject}_desc-preproc_dwi.mif" "${subject}_desc-meanDhollander_response-wm.txt" "${subject}_model-msmt_fod-wm.mif" "${subject}_desc-meanDhollander_response-gm.txt" "${subject}_model-msmt_fod-gm.mif" "${subject}_desc-meanDhollander_response-csf.txt" "${subject}_model-msmt_fod-csf.mif" -mask preproc_mask_resampled.mif -nthreads 32 -force
					mrconvert -coord 3 0 "${subject}_model-msmt_fod-wm.mif" - | mrcat "${subject}_model-msmt_fod-csf.mif" "${subject}_model-msmt_fod-gm.mif" - "${subject}_model-msmt_vf.mif" -force
					mtnormalise "${subject}_model-msmt_fod-wm.mif" "${subject}_model-msmt_desc-normalized_fod-wm.mif" "${subject}_model-msmt_fod-gm.mif" "${subject}_model-msmt_desc-normalized_fod-gm.mif" "${subject}_model-msmt_fod-csf.mif" "${subject}_model-msmt_desc-normalized_fod-csf.mif" -mask preproc_mask_resampled.mif -force
				fi
			else
				echo "No ${subject}_desc-preproc_dwi.nii.gz in $subject_dir/dwi"
			fi
        
		cd "$BIDS_DATASET" || exit 1
done
