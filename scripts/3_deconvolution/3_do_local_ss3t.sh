#!/bin/bash
#cd /network/iss/cohen/data/Ivan/Tractography/
cd workbench_GE
for patient_folder in */; do
        echo "Doing $patient_folder"
		cd "$patient_folder"        
            if [ -f "eddy_unwarped_images.nii.gz" ]; then
				if [ -f "Diff_preproc_unbiased.mif" ]; then
					
					ss3t_csd_beta1 Diff_preproc_unbiased.mif ../../mean_wm_dhollander_GE.txt wm_ss3t.mif ../../mean_gm_dhollander_GE.txt gm_ss3t.mif ../../mean_csf_dhollander_GE.txt csf_ss3t.mif -mask preproc_mask_resampled.mif -nthreads 32 -force
					mrconvert -coord 3 0 wm_ss3t.mif - | mrcat csf_ss3t.mif gm_ss3t.mif - vf.mif -force
					mtnormalise wm_ss3t.mif wmfod_norm.mif gm_ss3t.mif gm_norm.mif csf_ss3t.mif csf_norm.mif -mask preproc_mask_resampled.mif -force
				fi
			else
				echo "No eddy_unwarped_images.nii.gz in $patient_folder"
			fi
        
		cd ..
done
