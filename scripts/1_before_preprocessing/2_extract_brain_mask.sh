#!/bin/bash
# filepath: /network/iss/cohen/data/Ivan/Tractography/scripts/iterators/apply_hd_bet.sh

# List of subject folders to process (modify and add trailing "/" if needed)


# Loop over each subject folder
#cd workbench_GE
for patient_folder in */; do
    echo "Processing ${patient_folder} ..."
    if [ -d "${patient_folder}" ]; then
    cd "${patient_folder}"
        # Change into the patient folder's INPUTS directory
        
            if [ -f "T1_raw.nii.gz" ]; then
                echo "Applying HD-BET on T1_raw.nii in working directory"
                # Unzip the T1_raw.nii.gz file
                gunzip -k T1_raw.nii.gz
                hd-bet -i T1_raw.nii -o preproc_mask.nii.gz -device cpu --disable_tta
                # Alternaively you can use the classic BET with 
                #bet "$input_b0" preproc.nii.gz -n -m -f 0.4
                

            else
                echo "T1_CAT12.nii not found in working directory"
            fi
            # Return to parent directory
        cd ../
        
    else
        echo "${patient_folder} is not a valid directory."
    fi
done

