#!/bin/bash
for patient_folder in */; do
#subjects=("5214057347/" "5416131513_2" "8006408319/" "8009047562_1/" "8009501720/" "8009671832/" "8010484315/" "8010633600/" "8013375578/")
##for patient_folder in "${subjects[@]}"; do
	if [ -d "$patient_folder" ]; then
        echo "Doing $patient_folder"
		cd "$patient_folder"        
			#mrview Diff_preproc_unbiased.mif #-overlay.load 5tt_coreg.mif -overlay.colourmap 1
			# check if FA.nii exists
			#if [ -f "FA_in_MNI_via_T1.nii" ]; then
				#mkdir /home/ivan.mindlin/Desktop/Reg_GM_CSF_check/workbench_GE/$patient_folder
				#mrview meanb0_post_preproc.nii -overlay.load T1_in_dwi_space.nii.gz -overlay.threshold_max 0.5
				#mrview T1_in_dwi_space.nii.gz -plane 2 -size 2048,1024 -autoscale -odf.load_sh wmfod_norm.mif 
				#mrview T1_in_dwi_space.nii.gz -plane 2 -size 2048,1024 -autoscale -overlay.load Tian_in_dwi_space_warped.nii.gz -overlay.load /network/iss/cohen/data/Ivan/Tractography/freesurfer/$patient_folder/mri/schaefer100-yeo17.nii.gz 
				#mrview T1_in_dwi_space.nii.gz -mode 2 -size 2048,1024 -autoscale -tractography.load smallerTracks_200k_csd.tck -tractography.load smallerTracks_200k_norm.tck
				# Unzip overwriting file
				
				#mrview FA_in_MNI_via_T1.nii -tractography.load /network/iss/cohen/data/Ivan/Tractography/Normative_Model/dTOR_subset_100k.tck -overlay.load FA_in_MNI_via_T1.nii
				mrview Diff_preproc_unbiased.mif -overlay.load 5tt_nocoreg.mif #-overlay.colourmap 2 -overlay.load 5tt_coreg.mif -overlay.colourmap 1
 
				
			#fi			
		cd ..
	fi
done
