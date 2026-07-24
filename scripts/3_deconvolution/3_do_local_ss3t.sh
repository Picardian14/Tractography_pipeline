#!/bin/bash
###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
BIDS_DATASET="${BIDS_DATASET:-${BIDS_ROOT}}"
RESPONSE_DIR="${RESPONSE_DIR:-${BIDS_ROOT}}"
cd "$BIDS_DATASET" || exit 1
for subject_dir in sub-*/; do
        [ -d "$subject_dir/dwi" ] || continue
        echo "Doing $subject_dir"
		cd "$subject_dir/dwi" || continue
            if [ -f "eddy_unwarped_images.nii.gz" ]; then
				if [ -f "Diff_preproc_unbiased.mif" ]; then
					
					ss3t_csd_beta1 Diff_preproc_unbiased.mif "$RESPONSE_DIR/mean_wm_dhollander.txt" wm_ss3t.mif "$RESPONSE_DIR/mean_gm_dhollander.txt" gm_ss3t.mif "$RESPONSE_DIR/mean_csf_dhollander.txt" csf_ss3t.mif -mask preproc_mask_resampled.mif -nthreads 32 -force
					mrconvert -coord 3 0 wm_ss3t.mif - | mrcat csf_ss3t.mif gm_ss3t.mif - vf.mif -force
					mtnormalise wm_ss3t.mif wmfod_norm.mif gm_ss3t.mif gm_norm.mif csf_ss3t.mif csf_norm.mif -mask preproc_mask_resampled.mif -force
				fi
			else
				echo "No eddy_unwarped_images.nii.gz in $subject_dir/dwi"
			fi
        
		cd "$BIDS_DATASET" || exit 1
done
