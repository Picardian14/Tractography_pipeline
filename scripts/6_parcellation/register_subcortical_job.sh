#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=06:00:00

# Register a subcortical atlas once, then reuse it across cortical atlases.
set -eo pipefail
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID/ses-ID" >&2
    exit 2
fi

ml FreeSurfer/6.0.0
ml FSL
ml ANTs
ml MRtrix

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
ATLAS_ROOT="${ATLAS_ROOT:-$PIPELINE_ROOT/templates_parcellations}"
SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-$PIPELINE_ROOT/freesurfer}"
SUBCORTICAL_LABEL_NAME="${SUBCORTICAL_LABEL_NAME:-tians2}"
NTHREADS="${NTHREADS:-${SLURM_CPUS_PER_TASK:-4}}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="$NTHREADS"
export ANTS_RANDOM_SEED="${ANTS_RANDOM_SEED:-1}"

# The original Tian 3T volumes are MNI152NLin6Asym, matching FSL MNI152.
# A custom atlas must supply its own matching anatomical template explicitly.
if [ -z "${SUBCORTICAL_ATLAS:-}" ]; then
    case "$SUBCORTICAL_LABEL_NAME" in
        tians[123])
            scale="${SUBCORTICAL_LABEL_NAME#tians}"
            SUBCORTICAL_ATLAS="$ATLAS_ROOT/$SUBCORTICAL_LABEL_NAME/volume/Tian_Subcortex_S${scale}_3T_1mm.nii.gz"
            SUBCORTICAL_TEMPLATE="${SUBCORTICAL_TEMPLATE:-$FSLDIR/data/standard/MNI152_T1_1mm_brain.nii.gz}"
            ;;
        *) echo "Set SUBCORTICAL_ATLAS and SUBCORTICAL_TEMPLATE for this atlas." >&2; exit 2 ;;
    esac
elif [ -z "${SUBCORTICAL_TEMPLATE:-}" ]; then
    echo "SUBCORTICAL_TEMPLATE must match the supplied SUBCORTICAL_ATLAS space." >&2
    exit 2
fi

session_dir="$(readlink -f "$1")"
subject_id="$(basename "$(dirname "$session_dir")")"
fs_subject_id="${subject_id}_$(basename "$session_dir")"
t1_native="$session_dir/anat/${subject_id}_T1w.nii.gz"
fs_brain="$SUBJECTS_DIR/$fs_subject_id/mri/brain.mgz"
SUBCORTICAL_NATIVE="${SUBCORTICAL_NATIVE:-$session_dir/anat/${subject_id}_atlas-${SUBCORTICAL_LABEL_NAME}_space-T1w_labels.nii.gz}"
work_dir="$session_dir/anat/registration_${SUBCORTICAL_LABEL_NAME}"
for input in "$t1_native" "$fs_brain" "$SUBCORTICAL_ATLAS" "$SUBCORTICAL_TEMPLATE"; do
    if [ ! -s "$input" ]; then
        echo "Missing input: $input" >&2
        exit 1
    fi
done
mkdir -p "$work_dir" "$(dirname "$SUBCORTICAL_NATIVE")"

# recon-all must have used this session's T1. Conformation changes its grid,
# but retains scanner coordinates; this reslicing is not a new registration.
mrtransform "$fs_brain" "$work_dir/T1w_brain.nii.gz" \
    -template "$t1_native" -interp linear -datatype float32 -force

# Fit continuous anatomical intensities, never the discrete parcel image.
# Fixed = subject, moving = atlas template: the forward chain maps labels
# directly from template to native T1, with no inverse-warp ambiguity.
registration_prefix="$work_dir/template_to_T1w_"
antsRegistrationSyN.sh -d 3 -f "$work_dir/T1w_brain.nii.gz" \
    -m "$SUBCORTICAL_TEMPLATE" -o "$registration_prefix" -t s -n "$NTHREADS"
antsApplyTransforms -d 3 -i "$SUBCORTICAL_ATLAS" -r "$t1_native" \
    -o "$work_dir/subcortex_registered.nii.gz" \
    -t "${registration_prefix}1Warp.nii.gz" \
    -t "${registration_prefix}0GenericAffine.mat" \
    -n NearestNeighbor --default-value 0
mrconvert "$work_dir/subcortex_registered.nii.gz" "$SUBCORTICAL_NATIVE" \
    -datatype uint32 -force

printf 'subject\t%s\natlas\t%s\ntemplate\t%s\nfixed\t%s\nseed\t%s\nthreads\t%s\n' \
    "$fs_subject_id" "$SUBCORTICAL_ATLAS" "$SUBCORTICAL_TEMPLATE" "$t1_native" \
    "$ANTS_RANDOM_SEED" "$NTHREADS" > "$work_dir/registration.tsv"
echo "Registered subcortex: $SUBCORTICAL_NATIVE"
echo "Inspect template_to_T1w_Warped.nii.gz and native labels on the T1 before analysis."
