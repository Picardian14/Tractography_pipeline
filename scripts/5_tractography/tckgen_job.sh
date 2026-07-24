#!/bin/bash
#SBATCH --partition=medium
#SBATCH --cpus-per-task=8

#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

# Parameters to pass by command line to sbatch:
# --job-name
# --output
# --error
# --mem
# --time

module load MRtrix
module load FSL
module load FreeSurfer
module load python/3.8

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"

subject_dir=$1
subject_id=$(basename "$subject_dir")
cd "$subject_dir/dwi" || exit 1
echo "Job Doing $subject_id"

if [ -f "wmfod_norm.mif" ]; then
    tckgen -act 5tt_coreg.mif -backtrack -seed_gmwmi gmwmSeed_coreg.mif -nthreads 8 -select 10000000 wmfod_norm.mif tracks_10M_norm.tck -force
    tckedit tracks_10M_norm.tck -number 200k smallerTracks_200k_norm.tck -force
    tcksift2 -act 5tt_coreg.mif -out_mu sift_mu_norm.txt -out_coeffs sift_coeffs_norm.txt -nthreads 8 tracks_10M_norm.tck wmfod_norm.mif sift_10M_norm.txt -force
else
    echo "wmfod_norm.mif not found in $subject_dir/dwi"
fi
