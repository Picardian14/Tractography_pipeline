#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=ALL

# Usage: MODEL=ss3t bash parcellate_schaefer_tian_job.sh /path/to/sub-ID/ses-ID
# Operations only: quality-control commands are in SCHAEFER_TIAN.md.
set -eo pipefail

ml FreeSurfer/6.0.0
ml FSL
ml ANTs
ml MRtrix
export NO_FSFAST=1
source "$FREESURFER_HOME/SetUpFreeSurfer.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
export SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-${PIPELINE_ROOT}/freesurfer}"
MODEL="${MODEL:-ss3t}" # ss3t or msmt; use the matching tractogram and SIFT2 weights.
NTHREADS="${NTHREADS:-${SLURM_CPUS_PER_TASK:-4}}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="$NTHREADS"
export ANTS_RANDOM_SEED="${ANTS_RANDOM_SEED:-1}"

ATLAS_LABEL_NAME="${ATLAS_LABEL_NAME:-schaefer100-yeo7}"
ATLAS_ROOT="${ATLAS_ROOT:-${PIPELINE_ROOT}/templates_parcellations}"
ATLAS_DIR="${ATLAS_DIR:-${ATLAS_ROOT}/${ATLAS_LABEL_NAME}}"
TABLE_LABEL_NAME="${TABLE_LABEL_NAME:-LUT_${ATLAS_LABEL_NAME}}"
SUBCORTICAL_LABEL_NAME="${SUBCORTICAL_LABEL_NAME:-tianS1-3T}"
SUBCORTICAL_ATLAS="${SUBCORTICAL_ATLAS:-${ATLAS_ROOT}/tian_S1_3T/Tian_Subcortex_S1_3T.nii}"
SUBCORTICAL_LUT="${SUBCORTICAL_LUT:-${ATLAS_ROOT}/tian_S1_3T/LUT_Tian_Subcortex_S1_3T.txt}"
# The original Tian 3T atlas uses MNI152NLin6Asym, matching FSL's MNI152.
SUBCORTICAL_TEMPLATE="${SUBCORTICAL_TEMPLATE:-${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz}"

session_dir="$(readlink -f "$1")"
subject_id="$(basename "$(dirname "$session_dir")")"
session_id="$(basename "$session_dir")"
fs_subject_id="${subject_id}_${session_id}"
fs_subject_dir="${SUBJECTS_DIR}/${fs_subject_id}"
dwi_dir="${session_dir}/dwi"
t1_native="${session_dir}/anat/${subject_id}_T1w.nii.gz"
combined_atlas="${ATLAS_LABEL_NAME}-${SUBCORTICAL_LABEL_NAME}"
work_dir="${dwi_dir}/parcellation/${combined_atlas}"
output_prefix="${dwi_dir}/${subject_id}_atlas-${combined_atlas}"
connectome_prefix="${dwi_dir}/${subject_id}_model-${MODEL}_atlas-${combined_atlas}"
mkdir -p "$work_dir"

echo "Joining ${ATLAS_LABEL_NAME} and ${SUBCORTICAL_LABEL_NAME} for ${fs_subject_id} (${MODEL})"

# Define cortical IDs from the atlas table, never from the labels surviving a
# subject's reconstruction. Ignore the aseg structures inherited by aparc2aseg.
awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+Networks_(LH|RH)_/ {print}' \
    "$ATLAS_DIR/${TABLE_LABEL_NAME}.txt" | sort -n -k1,1 \
    > "$work_dir/cortex_input_lut.txt"
awk 'BEGIN {OFS="\t"} {print NR, $2, $3, $4, $5, $6}' \
    "$work_dir/cortex_input_lut.txt" > "$work_dir/cortex_output_lut.txt"
n_cortex="$(wc -l < "$work_dir/cortex_output_lut.txt")"

awk '$1 ~ /^[0-9]+$/ && $1 > 0 {print}' "$SUBCORTICAL_LUT" | sort -n -k1,1 \
    > "$work_dir/subcortex_input_lut.txt"
awk -v offset="$n_cortex" 'BEGIN {OFS="\t"} {print offset + NR, $2, $3, $4, $5, $6}' \
    "$work_dir/subcortex_input_lut.txt" > "$work_dir/subcortex_output_lut.txt"
cat "$work_dir/cortex_output_lut.txt" "$work_dir/subcortex_output_lut.txt" \
    > "${output_prefix}_lut.txt"

# Document every expected node, including any node absent in an individual.
awk -v cortex="$ATLAS_LABEL_NAME" -v subcortex="$SUBCORTICAL_LABEL_NAME" \
    -v offset="$n_cortex" '
    BEGIN {OFS="\t"; print "index", "name", "hemisphere", "source", "source_index"}
    FNR == NR {
        print FNR, $2, ($2 ~ /_LH_/ ? "L" : "R"), cortex, $1
        next
    }
    {print offset + FNR, $2, ($2 ~ /-lh$/ ? "L" : ($2 ~ /-rh$/ ? "R" : "NA")), subcortex, $1}
' "$work_dir/cortex_input_lut.txt" "$work_dir/subcortex_input_lut.txt" \
    > "${output_prefix}_nodes.tsv"

# Retain the subject's surface-derived cortical boundaries.
for hemi in lh rh; do
    mri_surf2surf --srcsubject fsaverage --trgsubject "$fs_subject_id" --hemi "$hemi" \
        --sval-annot "$ATLAS_DIR/${hemi}.${ATLAS_LABEL_NAME}.annot" \
        --tval "$fs_subject_dir/label/${hemi}.${ATLAS_LABEL_NAME}.annot"
done
mri_aparc2aseg --s "$fs_subject_id" --annot "$ATLAS_LABEL_NAME" \
    --o "$work_dir/cortex_aparc+aseg.mgz"
labelconvert "$work_dir/cortex_aparc+aseg.mgz" \
    "$work_dir/cortex_input_lut.txt" "$work_dir/cortex_output_lut.txt" \
    "$work_dir/cortex_space-fsnative.nii.gz" -force

# FreeSurfer conformation changes the voxel grid. Reslice using scanner-space
# headers onto the exact original T1 grid used for the existing T1-to-DWI map.
# This assumes recon-all used this session's T1, as in recon_all_job.sh.
mrtransform "$work_dir/cortex_space-fsnative.nii.gz" \
    "$work_dir/cortex_space-T1w.nii.gz" \
    -template "$t1_native" -interp nearest -datatype uint32 -force
mrtransform "$fs_subject_dir/mri/brain.mgz" "$work_dir/T1w_brain.nii.gz" \
    -template "$t1_native" -interp linear -datatype float32 -force

# Fit anatomy, not the discrete atlas. Do not reuse preprocessing's affine-only
# T1_to_MNI transform as a nonlinear subject-to-template registration.
registration_prefix="$work_dir/T1w_to_subcortical_template_"
antsRegistrationSyN.sh -d 3 -f "$SUBCORTICAL_TEMPLATE" \
    -m "$work_dir/T1w_brain.nii.gz" -o "$registration_prefix" \
    -t s -n "$NTHREADS"

# Invert the T1-to-template chain: inverse affine first on the command line,
# then inverse deformation. Nearest neighbour preserves discrete atlas IDs.
antsApplyTransforms -d 3 -i "$SUBCORTICAL_ATLAS" \
    -r "$t1_native" -o "$work_dir/subcortex_space-T1w_labels.nii.gz" \
    -t "[${registration_prefix}0GenericAffine.mat,1]" \
    -t "${registration_prefix}1InverseWarp.nii.gz" \
    -n NearestNeighbor --default-value 0
labelconvert "$work_dir/subcortex_space-T1w_labels.nii.gz" \
    "$work_dir/subcortex_input_lut.txt" "$work_dir/subcortex_output_lut.txt" \
    "$work_dir/subcortex_space-T1w_nodes.nii.gz" -force

# Both inputs now occupy the original T1 grid. Cortex wins at overlaps, so an
# external atlas cannot replace a surface-derived cortical parcel boundary.
mrcalc "$work_dir/cortex_space-T1w.nii.gz" 0 -gt \
    "$work_dir/cortex_space-T1w.nii.gz" "$work_dir/subcortex_space-T1w_nodes.nii.gz" \
    -if "${output_prefix}_space-T1w_parcels.nii.gz" -datatype uint32 -force

# Apply the established ACT/T1-to-DWI mapping once to the merged nodes, using
# the final mean b0 grid and nearest-neighbour interpolation for all labels.
mrtransform "${output_prefix}_space-T1w_parcels.nii.gz" \
    "${output_prefix}_space-dwi_parcels.nii.gz" \
    -linear "$dwi_dir/rigid_T1toDWI.txt" -template "$dwi_dir/mean_b0_final.nii.gz" \
    -interp nearest -datatype uint32 -force

tck2connectome "$dwi_dir/${subject_id}_model-${MODEL}_tractogram-10M.tck" \
    "${output_prefix}_space-dwi_parcels.nii.gz" "${connectome_prefix}_connectome.csv" \
    -tck_weights_in "$dwi_dir/${subject_id}_model-${MODEL}_sift2-weights.txt" \
    -out_assignments "${connectome_prefix}_assignments.csv" \
    -assignment_radial_search 4 -symmetric -zero_diagonal \
    -nthreads "$NTHREADS" -force
