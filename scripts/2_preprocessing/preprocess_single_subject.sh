#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=outputs/control_%A_%a.out.txt
#SBATCH --error=outputs/control_%A_%a.err.txt
#SBATCH --mail-user=ivan.mindlin@icm-institute.org
#SBATCH --mail-type=FAIL,END

# Single subject preprocessing
# Usage: sbatch preprocess_single_subject.sh SESSION_DIR [synb0|reversepe] [REVERSE_B0]

set -eo pipefail

PREPROCESSING_START_TIME=$(date +%s)

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 SESSION_DIR [synb0|reversepe] [REVERSE_B0.nii.gz]" >&2
    exit 2
fi
SDC_METHOD="${2:-synb0}"
REVERSE_B0="${3:-}"
case "$SDC_METHOD" in
    synb0|reversepe) ;;
    *) echo "Unknown preprocessing method: $SDC_METHOD (use synb0 or reversepe)" >&2; exit 2 ;;
esac
if [ "$SDC_METHOD" = synb0 ] && [ -n "$REVERSE_B0" ]; then
    echo "REVERSE_B0 is only used with reversepe." >&2
    exit 2
fi

module load MRtrix
module load FSL
module load ANTs
module load FreeSurfer/6.0.0
module load singularity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
MNI_TEMPLATE="${MNI_TEMPLATE:-${PIPELINE_ROOT}/templates_parcellations/MNI152_T1_2mm.nii.gz}"
SYNB0_SIF="${SYNB0_SIF:-${PIPELINE_ROOT}/images/synb0-disco_v3.0.sif}"

# Get parameters
SESSION_DIR=$(readlink -f "$1")
SUBJECT_DIR=$(dirname "$SESSION_DIR")
SUBJECT_NAME=$(basename "$SUBJECT_DIR")
SESSION_NAME=$(basename "$SESSION_DIR")


echo "=========================================="
echo "Processing session: ${SUBJECT_NAME}_${SESSION_NAME}"
echo "Working directory: $SESSION_DIR"
echo "Distortion correction: $SDC_METHOD"
echo "=========================================="

ANAT_DIR="$SESSION_DIR/anat"
DWI_DIR="$SESSION_DIR/dwi"
METHOD_DIR="$DWI_DIR/preprocessing/$SDC_METHOD"
if [ "$SDC_METHOD" = reversepe ]; then
    if [ -z "$REVERSE_B0" ]; then
        shopt -s nullglob
        reverse_candidates=("$DWI_DIR"/*_acq-inverted*_b0.nii.gz "$SESSION_DIR"/fmap/*_epi.nii.gz)
        shopt -u nullglob
        if [ "${#reverse_candidates[@]}" -ne 1 ]; then
            echo "Expected one dwi/*_acq-inverted*_b0.nii.gz or fmap/*_epi.nii.gz; specify REVERSE_B0 explicitly." >&2
            exit 1
        fi
        REVERSE_B0="${reverse_candidates[0]}"
    fi
    REVERSE_B0=$(readlink -f "$REVERSE_B0")
    if [[ "$REVERSE_B0" != *.nii.gz ]]; then
        echo "REVERSE_B0 must be a .nii.gz image." >&2
        exit 2
    fi
    REVERSE_JSON="${REVERSE_B0%.nii.gz}.json"
    for required_file in "$REVERSE_B0" "$REVERSE_JSON"; do
        if [ ! -f "$required_file" ]; then
            echo "Missing reverse-PE B0 input: $required_file" >&2
            exit 1
        fi
    done
fi
T1_FILE=$(find "$ANAT_DIR" -maxdepth 1 -type f \
    -name "${SUBJECT_NAME}*_T1w.nii.gz" \
    ! -name "${SUBJECT_NAME}_desc-hdbet_T1w.nii.gz" \
    ! -name "${SUBJECT_NAME}_desc-hdbet_T1w_mask.nii.gz" \
    -print -quit 2>/dev/null)
mapfile -t dwi_candidates < <(find "$DWI_DIR" -maxdepth 1 -type f \
    -name "${SUBJECT_NAME}*_dwi.nii.gz" \
    ! -name "${SUBJECT_NAME}*_desc-preproc_dwi.nii.gz" \
    ! -path "$REVERSE_B0" -print 2>/dev/null)
if [ "${#dwi_candidates[@]}" -ne 1 ]; then
    echo "Expected exactly one primary DWI series in $DWI_DIR (excluding REVERSE_B0)." >&2
    exit 1
fi
DWI_FILE="${dwi_candidates[0]}"
DWI_STEM="${DWI_FILE%.nii.gz}"
DWI_JSON="${DWI_STEM}.json"
BVAL_FILE="${DWI_STEM}.bval"
BVEC_FILE="${DWI_STEM}.bvec"
for required_file in "$T1_FILE" "$DWI_FILE" "$DWI_JSON" "$BVAL_FILE" "$BVEC_FILE"; do
    if [ -z "$required_file" ] || [ ! -f "$required_file" ]; then
        echo "Missing required BIDS input: $required_file" >&2
        exit 1
    fi
done
if [ "$SDC_METHOD" = synb0 ] && [ ! -f "$SYNB0_SIF" ]; then
    echo "Missing Synb0 container: $SYNB0_SIF" >&2
    exit 1
fi

# Both methods share denoising and publish to the same active filenames.
exec 9>"$DWI_DIR/.preprocessing.lock"
flock -n 9 || { echo "Preprocessing is already running for $SESSION_DIR" >&2; exit 1; }
mkdir -p "$METHOD_DIR"
cd "$DWI_DIR"


PREPROC_DWI_MIF="${SUBJECT_NAME}_desc-preproc_dwi.mif"
PREPROC_DWI_NII="${SUBJECT_NAME}_desc-preproc_dwi.nii.gz"
PREPROC_BVAL="${SUBJECT_NAME}_desc-preproc_dwi.bval"
PREPROC_BVEC="${SUBJECT_NAME}_desc-preproc_dwi.bvec"
DWI_B0_MASK_NII="${SUBJECT_NAME}_desc-preproc_b0_mask.nii.gz"
T1_BRAIN_NII="${ANAT_DIR}/${SUBJECT_NAME}_desc-hdbet_T1w.nii.gz"
T1_MASK_NII="${ANAT_DIR}/${SUBJECT_NAME}_desc-hdbet_T1w_bet.nii.gz"
T1_MASK_DWI_MIF="${SUBJECT_NAME}_desc-resampled_bet.mif"
T1_IN_DWI_NII="${METHOD_DIR}/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz"

echo "Current working directory: $(pwd)"

# Store input info in a log file for reference
cat > "${METHOD_DIR}/${SUBJECT_NAME}_desc-preprocessing_info.txt" << EOF
SUBJECT_NAME: $SUBJECT_NAME
SESSION_NAME: $SESSION_NAME
SUBJECT_DIR: $SUBJECT_DIR
SESSION_DIR: $SESSION_DIR
DWI_JSON: $DWI_JSON
SDC_METHOD: $SDC_METHOD
REVERSE_B0: $REVERSE_B0
PROCESSING_DATE: $(date)
EOF

echo "Input info saved to ${SUBJECT_NAME}_desc-preprocessing_info.txt"

##############################################
# STEP 1: Extract the T1 brain and mask with HD-BET
##############################################
echo ""
echo "Step 1: Extracting the T1 brain mask with HD-BET..."

if [ -f "$T1_BRAIN_NII" ] && [ -f "$T1_MASK_NII" ]; then
    echo "  - HD-BET outputs already exist, skipping brain extraction."
else
    ANAT_BIND_DIR=$(readlink -f "$ANAT_DIR")
    T1_NAME=$(basename "$T1_FILE")

    singularity exec \
        --bind "${ANAT_BIND_DIR}:/anat" \
        "${PIPELINE_ROOT}/images/diffusion_image.sif" \
        hd-bet -i "/anat/${T1_NAME}" -o "/anat/${SUBJECT_NAME}_desc-hdbet_T1w.nii.gz" --save_bet_mask -device cpu --disable_tta
    if [ $? -ne 0 ]; then
        echo "ERROR: HD-BET failed for $SUBJECT_NAME" >&2
        exit 1
    fi
fi

if [ ! -f "$T1_BRAIN_NII" ] || [ ! -f "$T1_MASK_NII" ]; then
    echo "ERROR: Expected HD-BET outputs were not created for $SUBJECT_NAME" >&2
    exit 1
fi

##############################################
# STEP 2: Convert to MRtrix and denoise
##############################################
echo ""
echo "Step 2: Converting to MRtrix format and denoising..."
if [ ! -f "Diff.mif" ]; then
    echo "  - Converting DWI to MRtrix format..."
    mrconvert "$DWI_FILE" Diff.mif -fslgrad "$BVEC_FILE" "$BVAL_FILE" -force
fi
# Denoise with extent 7 (similar to Siemens pipeline).
if [ ! -f "Diff_den.mif" ]; then
    dwidenoise Diff.mif Diff_den.mif -extent 7 -noise noise.mif -force
    # Residuals help identify removal of anatomical signal.
    mrcalc Diff.mif Diff_den.mif -subtract residual.mif -force
fi
if [ ! -f "Diff_den_gibbs.mif" ]; then
    mrdegibbs Diff_den.mif Diff_den_gibbs.mif -force
fi
##############################################
# STEP 3: Prepare the selected distortion-correction inputs
##############################################
echo ""
echo "Step 3: Preparing $SDC_METHOD inputs..."

# Everything depending on distortion correction stays in this method's folder.
cd "$METHOD_DIR"
mkdir -p INPUTS OUTPUTS
acqparams_args=("$DWI_JSON" INPUTS/acqparams.txt)
if [ "$SDC_METHOD" = reversepe ]; then
    acqparams_args+=("$REVERSE_JSON")
fi
PHASE_ENCODING_DIRECTION=$(
    python3 "${PIPELINE_ROOT}/scripts/2_preprocessing/create_acqparams.py" "${acqparams_args[@]}"
)

dwiextract "$DWI_DIR/Diff_den_gibbs.mif" - -bzero -force | \
    mrmath - mean mean_b0.mif -axis 3 -force
mrconvert mean_b0.mif INPUTS/b0.nii.gz -force

DEFAULT_FRACTION_BET=0.4
bet INPUTS/b0.nii.gz "$DWI_B0_MASK_NII" -n -m -f "$DEFAULT_FRACTION_BET"
mv "${DWI_B0_MASK_NII%.nii.gz}_mask.nii.gz" "$DWI_B0_MASK_NII"

if [ "$SDC_METHOD" = synb0 ]; then
    cp "$T1_FILE" INPUTS/T1.nii.gz
else
    # Check B0-only content before averaging. Compare against the exported
    # primary B0, which is the actual spatial reference supplied to TOPUP.
    REGRID_REVERSE=$(
    python3 - INPUTS/b0.nii.gz "$REVERSE_B0" <<'PY_REVERSE'
import sys
from pathlib import Path
import nibabel as nib
import numpy as np

dwi = nib.load(sys.argv[1])
reverse_b0 = nib.load(sys.argv[2])
if len(reverse_b0.shape) not in (3, 4):
    sys.exit("Reverse B0 must be a 3D image or a 4D B0-only series.")
bval_file = Path(sys.argv[2][:-7] + ".bval")
if bval_file.exists():
    bvals = np.atleast_1d(np.loadtxt(bval_file)).ravel()
    nvolumes = reverse_b0.shape[3] if len(reverse_b0.shape) == 4 else 1
    if bvals.size != nvolumes or not np.all(np.isfinite(bvals)) or np.any(np.abs(bvals) > 50):
        sys.exit("REVERSE_B0 must contain only B0 volumes (|b| <= 50 s/mm²), with one b-value per volume.")
same_grid = dwi.shape[:3] == reverse_b0.shape[:3] and np.allclose(dwi.affine, reverse_b0.affine, rtol=0, atol=1e-4)
print("no" if same_grid else "yes")
PY_REVERSE
    )
    # One mean per direction gives exactly two images and two acqparams rows.
    fslmaths "$REVERSE_B0" -Tmean INPUTS/reverse_b0_native.nii.gz
    if [ "$REGRID_REVERSE" = yes ]; then
        echo "  - Regridding reverse B0 onto the primary DWI grid (scanner coordinates)."
        # Resample using the existing image geometry; TOPUP estimates movement
        # and distortion. Sinc interpolation follows MRtrix's SE-EPI regridding.
        mrtransform INPUTS/reverse_b0_native.nii.gz - \
            -template INPUTS/b0.nii.gz -interp sinc -force | \
            mrcalc - 0 -max INPUTS/reverse_b0.nii.gz -datatype float32 -force
    else
        cp INPUTS/reverse_b0_native.nii.gz INPUTS/reverse_b0.nii.gz
    fi
    echo "REGRID_REVERSE: $REGRID_REVERSE" >> "${SUBJECT_NAME}_desc-preprocessing_info.txt"
    fslmerge -t INPUTS/b0_pair.nii.gz INPUTS/b0.nii.gz INPUTS/reverse_b0.nii.gz
fi

##############################################
# STEP 4: Estimate the distortion field
##############################################
echo ""
echo "Step 4: Estimating the distortion field with $SDC_METHOD..."

if [ ! -f "OUTPUTS/topup_fieldcoef.nii.gz" ] || [ ! -f "OUTPUTS/topup_movpar.txt" ]; then
    if [ "$SDC_METHOD" = synb0 ]; then
        singularity run -e -B INPUTS/:/INPUTS -B OUTPUTS/:/OUTPUTS \
            -B "$FREESURFER_HOME/license.txt:/extra/freesurfer/license.txt" "$SYNB0_SIF"
    else
        # Full-resolution estimation also supports odd grids such as 120x120x69;
        # the default factor-two subsampling cannot be used on those grids.
        read -r nx ny nz <<< "$(mrinfo INPUTS/b0.nii.gz -size)"
        topup_grid_options=()
        if (( nx % 2 || ny % 2 || nz % 2 )); then
            topup_grid_options+=(--subsamp=1,1,1,1,1,1,1,1,1)
        fi
        topup --imain=INPUTS/b0_pair.nii.gz \
            --datain=INPUTS/acqparams.txt \
            --config=b02b0.cnf \
            --out=OUTPUTS/topup \
            --iout=OUTPUTS/b0_unwarped "${topup_grid_options[@]}"
    fi
else
    echo "  - $SDC_METHOD TOPUP outputs already exist, skipping field estimation."
fi

##############################################
# STEP 5: Prepare for eddy
##############################################
echo ""
echo "Step 5: Preparing for eddy correction..."

# Use identical DWI preparation for both methods and either PE polarity.
input_dwi="$DWI_DIR/Diff_den_gibbs.mif"
output=$(mrinfo "$input_dwi" -size)
nvolumes=$(echo "$output" | awk '{print $4}')
ones=$(printf '1 %.0s' $(seq 1 $nvolumes))
echo "$ones" > eddy_indices.txt

# Convert to NIfTI for eddy
mrconvert "$input_dwi" Diff_eddy_in.nii.gz -force

##############################################
# STEP 6: Run eddy correction
##############################################
echo ""
echo "Step 6: Running eddy correction..."

# run eddy if files do not exist
if [ ! -f "eddy_unwarped_images.nii.gz" ] || [ ! -f "eddy_unwarped_images.eddy_rotated_bvecs" ]; then
    echo "  - Running eddy..."
    eddy --imain=Diff_eddy_in.nii.gz \
	     --mask="$DWI_B0_MASK_NII" \
     --acqp=INPUTS/acqparams.txt \
     --index=eddy_indices.txt \
     --bvecs="$BVEC_FILE" \
     --bvals="$BVAL_FILE" \
     --topup=OUTPUTS/topup \
     --out=eddy_unwarped_images \
     --verbose
    if [ $? -ne 0 ]; then
        echo "ERROR: eddy failed for $SUBJECT_NAME"
        exit 1
    fi
else
    echo "  - Eddy outputs already exist, skipping eddy step."
fi

totalSlices=$(echo "$output" | awk '{print $3 * $4}')
echo "Percentage of outlier slices (inspect high values during QC):"
awk -v total="$totalSlices" 'NR > 1 {for(i=1;i<=NF;i++) sum+=$i} END {printf "%.5f\n", 100 * sum / total}' \
    eddy_unwarped_images.eddy_outlier_map | tee percentageOutliers.txt


# Convert back to MRtrix format
mrconvert eddy_unwarped_images.nii.gz Diff_preproc.mif -fslgrad eddy_unwarped_images.eddy_rotated_bvecs "$BVAL_FILE" -force

##############################################
# STEP 7: Bias field correction
##############################################
echo ""
echo "Step 7: Bias field correction..."

dwibiascorrect ants Diff_preproc.mif Diff_preproc_unbiased.mif -bias bias.mif -force
mrconvert Diff_preproc_unbiased.mif "$PREPROC_DWI_MIF" -force
mrconvert "$PREPROC_DWI_MIF" "$PREPROC_DWI_NII" \
    -export_grad_fsl "$PREPROC_BVEC" "$PREPROC_BVAL" -force

##############################################
# STEP 8: Create the final b0 reference and register the T1 mask to DWI
##############################################
echo ""
echo "Step 8: Registering the HD-BET mask to final DWI space..."

# Eddy changes the DWI geometry, so the anatomical mask can only be placed on
# the final DWI grid after preprocessing. The brain-extracted T1 provides a
# cleaner cross-modal registration target than the unstripped anatomical image.
dwiextract "$PREPROC_DWI_MIF" - -bzero -force | \
    mrmath - mean mean_b0_final.mif -axis 3 -force
mrconvert mean_b0_final.mif mean_b0_final.nii.gz -force

flirt \
    -in "$T1_BRAIN_NII" \
    -ref mean_b0_final.nii.gz \
    -dof 6 \
    -omat rigid_T1toDWI.mat

transformconvert \
    rigid_T1toDWI.mat \
    "$T1_BRAIN_NII" \
    mean_b0_final.nii.gz \
    flirt_import \
    rigid_T1toDWI.txt

# Use the same transform for the anatomical image (QC) and its binary mask.
# Nearest-neighbour interpolation preserves the discrete mask labels.
mrtransform \
    "$T1_BRAIN_NII" \
    "$T1_IN_DWI_NII" \
    -linear rigid_T1toDWI.txt \
    -template "$PREPROC_DWI_MIF" \
    -force

mrtransform \
    "$T1_MASK_NII" \
    "$T1_MASK_DWI_MIF" \
    -linear rigid_T1toDWI.txt \
    -template "$PREPROC_DWI_MIF" \
    -interp nearest \
    -force

##############################################
# STEP 9: Compute FA
##############################################
echo ""
echo "Step 9: Computing FA map..."

# Compute tensor
dwi2tensor "$PREPROC_DWI_MIF" "${SUBJECT_NAME}_model-dti_tensor.mif" \
    -mask "$T1_MASK_DWI_MIF" -force

# Extract FA
tensor2metric "${SUBJECT_NAME}_model-dti_tensor.mif" \
    -fa "${SUBJECT_NAME}_model-dti_FA.mif" -force

# Convert to NIfTI
mrconvert "${SUBJECT_NAME}_model-dti_FA.mif" \
    "${SUBJECT_NAME}_model-dti_FA.nii.gz" -force

##############################################
# STEP 10: Register to MNI space
##############################################
echo ""
echo "Step 10: Registering FA to MNI space..."

##############################################
# OPTION A: Direct b0 to MNI (FLIRT - simpler)
##############################################
echo ""
echo "Step 10A: Direct b0 to MNI registration (FLIRT)..."

# run if file does not exist
if [ ! -f "mean_b0_in_MNI.nii.gz" ]; then
    echo "  Registering mean b0 to MNI..."
    flirt -in mean_b0_final.nii.gz \
      -ref "$MNI_TEMPLATE" \
      -out mean_b0_in_MNI.nii.gz \
      -omat b02standard.mat \
      -dof 12 \
      -cost mutualinfo
else
    echo "  mean_b0_in_MNI.nii.gz already exists, skipping registration."
fi


# Apply transform to FA
flirt -in "${SUBJECT_NAME}_model-dti_FA.nii.gz" \
      -ref "$MNI_TEMPLATE" \
      -applyxfm -init b02standard.mat \
      -out FA_in_MNI_direct.nii.gz \
      -interp trilinear

# Unzip FA_in_MNI_direct
gunzip -f FA_in_MNI_direct.nii.gz

echo "  - FA_in_MNI_direct.nii (direct b0->MNI registration)"

##############################################
# OPTION B: Via T1 using ANTs (more accurate)
##############################################
echo ""
echo "Step 10B: Registration via T1 using ANTs..."

# Check if T1_HDbet exists
if [ -f "$T1_BRAIN_NII" ]; then
    
    # Step 10b-i: Register T1 to MNI using ANTs
    # run if file does not exist
    if [ ! -f "T1_to_MNI_Warped.nii.gz" ]; then
         echo "  Registering T1 to MNI..."
        antsRegistrationSyNQuick.sh -d 3 \
            -f "$MNI_TEMPLATE" \
            -m "$T1_BRAIN_NII" \
            -o T1_to_MNI_ \
            -t a
        
    else
        echo "  T1 to MNI registration already exists, skipping."
    fi
    
    # Step 10b-ii: Register mean_b0 to T1 using ANTs (rigid)
    # run if file does not exist
    if [ ! -f "b0_to_T1_0GenericAffine.mat" ]; then
        
        echo "  Registering b0 to T1..."
        antsRegistrationSyNQuick.sh -d 3 \
            -f "$T1_BRAIN_NII" \
            -m mean_b0_final.nii.gz \
            -o b0_to_T1_ \
            -t r
    else
        echo "  b0 to T1 registration already exists, skipping."
    fi  
    
    # Step 10b-iii: Apply combined transforms to FA
    echo "  Applying combined transforms to FA..."
    antsApplyTransforms -d 3 \
        -i "${SUBJECT_NAME}_model-dti_FA.nii.gz" \
        -r "$MNI_TEMPLATE" \
        -o FA_in_MNI_via_T1.nii.gz \
        -t T1_to_MNI_0GenericAffine.mat \
        -t b0_to_T1_0GenericAffine.mat \
        -n Linear
    
    # Unzip FA_in_MNI_via_T1
    gunzip -f FA_in_MNI_via_T1.nii.gz
    
    echo "  - FA_in_MNI_via_T1.nii (ANTs via T1 registration)"
    echo "  - T1_in_MNI_Warped.nii.gz (warped T1 for verification)"
else
    echo "  WARNING: $T1_BRAIN_NII not found. Skipping ANTs via T1 option."
fi

echo ""
echo "Quality check files created:"
echo "  - mean_b0_in_MNI.nii.gz (check b0-MNI alignment)"
echo "  - FA_in_MNI_direct.nii (OPTION A: direct b0->MNI)"
echo "  - FA_in_MNI_via_T1.nii (OPTION B: via T1 using ANTs)"

# Preserve each method's results, but keep the established downstream names.
# Copy instead of linking so later commands cannot modify the saved variant.
active_outputs=(
    "$PREPROC_DWI_MIF" "$PREPROC_DWI_NII" "$PREPROC_BVAL" "$PREPROC_BVEC"
    Diff_preproc.mif Diff_preproc_unbiased.mif
    "$DWI_B0_MASK_NII" "$T1_MASK_DWI_MIF"
    mean_b0_final.mif mean_b0_final.nii.gz rigid_T1toDWI.mat rigid_T1toDWI.txt
    "${SUBJECT_NAME}_model-dti_tensor.mif"
    "${SUBJECT_NAME}_model-dti_FA.mif" "${SUBJECT_NAME}_model-dti_FA.nii.gz"
    mean_b0_in_MNI.nii.gz b02standard.mat
    T1_to_MNI_0GenericAffine.mat T1_to_MNI_Warped.nii.gz
    b0_to_T1_0GenericAffine.mat FA_in_MNI_direct.nii FA_in_MNI_via_T1.nii
    percentageOutliers.txt "${SUBJECT_NAME}_desc-preprocessing_info.txt"
)
# Check the complete set before replacing any active result.
for output in "${active_outputs[@]}" "$T1_IN_DWI_NII"; do
    if [ ! -f "$output" ]; then
        echo "Missing preprocessing output: $output; active results were not updated." >&2
        exit 1
    fi
done
for output in "${active_outputs[@]}"; do
    cp --remove-destination "$output" "$DWI_DIR/$output"
done
cp --remove-destination "$T1_IN_DWI_NII" "$ANAT_DIR/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz"
echo "Active preprocessing: $SDC_METHOD (saved in $METHOD_DIR)"
echo "Rerun downstream analyses for this selection; existing FODs/tractograms/connectomes are not updated here."

PREPROCESSING_END_TIME=$(date +%s)
PREPROCESSING_DURATION=$((PREPROCESSING_END_TIME - PREPROCESSING_START_TIME))
PREPROCESSING_HOURS=$((PREPROCESSING_DURATION / 3600))
PREPROCESSING_MINUTES=$(((PREPROCESSING_DURATION % 3600) / 60))
PREPROCESSING_SECONDS=$((PREPROCESSING_DURATION % 60))

echo ""
echo "=========================================="
echo "Session ${SUBJECT_NAME}_${SESSION_NAME} processing complete!"
echo "End time: $(date)"
printf "Total preprocessing time: %02d:%02d:%02d (HH:MM:SS)\n" \
    "$PREPROCESSING_HOURS" "$PREPROCESSING_MINUTES" "$PREPROCESSING_SECONDS"
echo "FA maps in MNI space:"
echo "  Option A (direct): $DWI_DIR/FA_in_MNI_direct.nii"
echo "  Option B (via T1): $DWI_DIR/FA_in_MNI_via_T1.nii"
echo "=========================================="
