#!/bin/bash
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

BIDS_ROOT="$(readlink -f "$1")"
cd "$BIDS_ROOT" || exit 1
for subject_dir in sub-*/; do
        [ -d "$subject_dir/dwi" ] || continue
        subject_start_time=$SECONDS
        echo "Doing $subject_dir"
		subject=$(basename "$subject_dir")
		cd "$subject_dir/dwi" || continue
            if [ -f "${subject}_desc-preproc_dwi.nii.gz" ]; then
				if [ -f "${subject}_desc-preproc_dwi.mif" ]; then
					ss3t_csd_beta1 "${subject}_desc-preproc_dwi.mif" "${subject}_desc-meanDhollander_response-wm.txt" "${subject}_model-ss3t_fod-wm.mif" "${subject}_desc-meanDhollander_response-gm.txt" "${subject}_model-ss3t_fod-gm.mif" "${subject}_desc-meanDhollander_response-csf.txt" "${subject}_model-ss3t_fod-csf.mif" -mask "${subject}_desc-resampled_bet.mif" -nthreads 32 -force
					mrconvert -coord 3 0 "${subject}_model-ss3t_fod-wm.mif" - | mrcat "${subject}_model-ss3t_fod-csf.mif" "${subject}_model-ss3t_fod-gm.mif" - "${subject}_model-ss3t_vf.mif" -force
					mtnormalise "${subject}_model-ss3t_fod-wm.mif" "${subject}_model-ss3t_desc-normalized_fod-wm.mif" "${subject}_model-ss3t_fod-gm.mif" "${subject}_model-ss3t_desc-normalized_fod-gm.mif" "${subject}_model-ss3t_fod-csf.mif" "${subject}_model-ss3t_desc-normalized_fod-csf.mif" -mask "${subject}_desc-resampled_bet.mif" -force
				fi
			else
				echo "No ${subject}_desc-preproc_dwi.nii.gz in $subject_dir/dwi"
			fi
        
		cd "$BIDS_ROOT" || exit 1
        subject_elapsed=$((SECONDS - subject_start_time))
        printf "Processing time for %s: %02d:%02d:%02d (HH:MM:SS)\n" \
            "$subject" \
            "$((subject_elapsed / 3600))" \
            "$(((subject_elapsed % 3600) / 60))" \
            "$((subject_elapsed % 60))"
done
