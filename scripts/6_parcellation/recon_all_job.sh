#!/bin/bash
#SBATCH --partition=medium
#SBATCH --cpus-per-task=4

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

# Parameters to pass by command line to sbatch:
# --job-name
# --output
# --error
# --mem
# --time

ml FreeSurfer/6.0.0
scanner_folder=$2
patient_folder=$1
data_folder=$3
cd "$data_folder"  
cd $scanner_folder/$patient_folder
echo "Job Doing $patient_folder"
export SUBJECTS_DIR="/network/iss/cohen/data/Ivan/Tractography/freesurfer"
· If subject folder in SUBJECTS_DIR does not exist, run recon-all
if [ ! -d "$SUBJECTS_DIR/$patient_folder" ]; then
    echo "Running recon-all for $patient_folder"
    recon-all -all -s $patient_folder -i T1_raw.nii.gz -parallel -openmp 4
else
    echo "Subject folder $SUBJECTS_DIR/$patient_folder already exists. Skipping recon-all."
fi