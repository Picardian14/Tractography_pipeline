#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

module load python/3.8

PIPELINE_ROOT=$3
source "${PIPELINE_ROOT}/scripts/paths_config.sh"

dicom_zip=$1
subject_label=$2

echo "Job Doing sub-$subject_label"
echo "Current working directory: $(pwd)"
dcm2bids_helper -d "$dicom_zip" -o "$(pwd)"
