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
# New structure supports different scanner types
# Usage: sbatch preprocess_single_subject.sh /bids/sub-ID SCANNER PIPELINE_ROOT

module load MRtrix
module load FSL
module load ANTs
module load FreeSurfer
module load singularity

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
# Note: Slurm #SBATCH paths cannot expand shell variables; submitter scripts set
# job output paths explicitly when site-specific absolute paths are needed.
###############################################################################
PIPELINE_ROOT=$3
source "${PIPELINE_ROOT}/scripts/paths_config.sh"

# Get parameters
SUBJECT_DIR=$1           # Full path to a BIDS sub-* directory
SCANNER_TYPE=$2          # Scanner type (GE, siemens)
SUBJECT_NAME=$(basename "$SUBJECT_DIR")


echo "=========================================="
echo "Processing subject: $SUBJECT_NAME"
echo "Scanner: $SCANNER_TYPE"
echo "Working directory: $SUBJECT_DIR"
echo "=========================================="

ANAT_DIR="$SUBJECT_DIR/anat"
DWI_DIR="$SUBJECT_DIR/dwi"
T1_FILE=$(find "$ANAT_DIR" -maxdepth 1 -type f -name "${SUBJECT_NAME}*_T1w.nii.gz" -print -quit 2>/dev/null)
DWI_FILE=$(find "$DWI_DIR" -maxdepth 1 -type f \
    -name "${SUBJECT_NAME}*_dwi.nii.gz" \
    ! -name "${SUBJECT_NAME}*_desc-preproc_dwi.nii.gz" \
    -print -quit 2>/dev/null)
DWI_STEM="${DWI_FILE%.nii.gz}"
BVAL_FILE="${DWI_STEM}.bval"
BVEC_FILE="${DWI_STEM}.bvec"

for required_file in "$T1_FILE" "$DWI_FILE" "$BVAL_FILE" "$BVEC_FILE"; do
    if [ -z "$required_file" ] || [ ! -f "$required_file" ]; then
        echo "Missing required BIDS input: $required_file" >&2
        exit 1
    fi
done

PREPROC_DWI_MIF="${SUBJECT_NAME}_desc-preproc_dwi.mif"
PREPROC_DWI_NII="${SUBJECT_NAME}_desc-preproc_dwi.nii.gz"
PREPROC_BVAL="${SUBJECT_NAME}_desc-preproc_dwi.bval"
PREPROC_BVEC="${SUBJECT_NAME}_desc-preproc_dwi.bvec"
MASK_NII="${SUBJECT_NAME}_desc-brain_mask.nii.gz"
MASK_MIF="${SUBJECT_NAME}_desc-brain_mask.mif"

echo "Current working directory: $(pwd)"

# Store scanner type info in a log file for reference
cat > "${SUBJECT_NAME}_desc-preprocessing_info.txt" << EOF
SUBJECT_NAME: $SUBJECT_NAME
SCANNER_TYPE: $SCANNER_TYPE
SUBJECT_DIR: $SUBJECT_DIR
PROCESSING_DATE: $(date)
EOF

echo "Scanner info saved to ${SUBJECT_NAME}_desc-preprocessing_info.txt"

##############################################
# STEP 2: Convert to MRtrix and denoise
##############################################
echo ""
echo "Step 2: Converting to MRtrix format and denoising..."
#
mrconvert "$DWI_FILE" Diff.mif -fslgrad "$BVEC_FILE" "$BVAL_FILE" -force
#
## Denoise with extent 7 (similar to Siemens pipeline)
dwidenoise Diff.mif Diff_den_ext7.mif -extent 7 -noise noise_ext7.mif -force
#
## Calculate residuals for QC
mrcalc Diff.mif Diff_den_ext7.mif -subtract residual_ext7.mif -force
#
## Remove Gibbs ringing
mrdegibbs Diff_den_ext7.mif Diff_den_gibbs_ext7.mif -force
#
## Create simpler name for processed data
ln -sf Diff_den_gibbs_ext7.mif Diff_den_gibbs.mif
#
###############################################
## STEP 3: Prepare synb0-disco inputs
###############################################
#echo ""
echo "Step 3: Preparing synb0-disco inputs..."
#
mkdir -p INPUTS OUTPUTS
#
## Create acquisition parameters file
if [ "$SCANNER_TYPE" == "siemens" ]; then
    # Siemens: AP direction only
    cp "$SIEMENS_ACQPARAMS" INPUTS/acqparams.txt
    # Extract mean b0 from AP
    dwiextract Diff_den_gibbs.mif - -bzero -force | mrmath - mean mean_b0_AP.mif -axis 3 -force
    mrconvert mean_b0_AP.mif mean_b0_AP.nii.gz -force
    cp mean_b0_AP.nii.gz INPUTS/b0.nii.gz
elif [ "$SCANNER_TYPE" == "GE" ]; then
    # GE: AP direction only, different total readout time
    cp "$GE_ACQPARAMS" INPUTS/acqparams.txt
    # Extract mean b0 from PA
    dwiextract Diff_den_gibbs.mif - -bzero -force | mrmath - mean mean_b0_PA.mif -axis 3 -force
    mrconvert mean_b0_PA.mif mean_b0_PA.nii.gz -force
    cp mean_b0_PA.nii.gz INPUTS/b0.nii.gz
else
    echo "Unknown scanner type: $SCANNER_TYPE"
    exit 1
fi
#
#
#
cp "$T1_FILE" INPUTS/T1.nii.gz


##############################################
# STEP 4: Run synb0-disco
##############################################
echo ""
echo "Step 4: Running synb0-disco for distortion correction..."

if [ ! -f "OUTPUTS/topup_fieldcoef.nii.gz" ]; then
    
    singularity run -e -B INPUTS/:/INPUTS -B OUTPUTS/:/OUTPUTS -B $FREESURFER_HOME/license.txt:/extra/freesurfer/license.txt "$SYNB0_SIF"
    if [ $? -ne 0 ]; then
        echo "ERROR: synb0-disco failed for $SUBJECT"
        exit 1
    fi
else
    echo "synb0-disco already completed (outputs exist)"
fi

##############################################
# STEP 5: Prepare for eddy
##############################################
echo ""
echo "Step 5: Preparing for eddy correction..."

# Create eddy indices
if [ "$SCANNER_TYPE" == "siemens" ]; then
    input_dwi="Diff_den_gibbs.mif"
    printf "Using denoised data for Siemens scanner\n"
else
    input_dwi="Diff.mif"
    printf "Using raw data for GE scanner\n"
fi
output=$(mrinfo "$input_dwi" -size)
nvolumes=$(echo "$output" | awk '{print $4}')
ones=$(printf '1 %.0s' $(seq 1 $nvolumes))
echo "$ones" > eddy_indices.txt

# Convert to NIfTI for eddy
mrconvert "$input_dwi" Diff_eddy_in.nii.gz -force

# Create brain mask for eddy
echo "Creating brain mask..."
# Determine which b0 file exists.
if [ -f mean_b0_AP.nii.gz ]; then
    input_b0="mean_b0_AP.nii.gz"
elif [ -f mean_b0_PA.nii.gz ]; then
    input_b0="mean_b0_PA.nii.gz"
else
    echo "No mean b0 found in $SUBJECT_DIR" >&2
    exit 1
fi
# Extracted f
if [ ! -f "$MASK_NII" ]; then
    echo "  - Extracting brain mask from $input_b0..."
    hdbet_mask="${SUBJECT_NAME}_desc-hdbet_T1w_mask.nii.gz"
    if [ ! -f "$hdbet_mask" ]; then
        echo "  - $hdbet_mask not found. Please run 2_extract_brain_mask.sh first."
        exit 1
    fi
    cp "$hdbet_mask" "$MASK_NII"
else
    echo "  - Brain mask already exists, skipping extraction."
fi
mrconvert "$MASK_NII" "$MASK_MIF" -force


##############################################
# STEP 6: Run eddy correction
##############################################
echo ""
echo "Step 6: Running eddy correction..."

# run eddy if files do not exist
if [ ! -f "$PREPROC_DWI_NII" ]; then
    echo "  - Running eddy..."
    eddy --imain=Diff_eddy_in.nii.gz \
	     --mask="$MASK_NII" \
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
# STEP 8: Compute FA
##############################################
echo ""
echo "Step 8: Computing FA map..."

# Compute tensor
dwi2tensor "$PREPROC_DWI_MIF" "${SUBJECT_NAME}_model-dti_tensor.mif" \
    -mask "$MASK_MIF" -force

# Extract FA
tensor2metric "${SUBJECT_NAME}_model-dti_tensor.mif" \
    -fa "${SUBJECT_NAME}_model-dti_FA.mif" -force

# Convert to NIfTI
mrconvert "${SUBJECT_NAME}_model-dti_FA.mif" \
    "${SUBJECT_NAME}_model-dti_FA.nii.gz" -force

##############################################
# STEP 9: Register to MNI space
##############################################
echo ""
echo "Step 9: Registering FA to MNI space..."

# Extract mean b0 for registration
dwiextract "$PREPROC_DWI_MIF" - -bzero -force | mrmath - mean mean_b0_final.mif -axis 3 -force
mrconvert mean_b0_final.mif mean_b0_final.nii.gz -force

##############################################
# OPTION A: Direct b0 to MNI (FLIRT - simpler)
##############################################
echo ""
echo "Step 9A: Direct b0 to MNI registration (FLIRT)..."

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
echo "Step 9B: Registration via T1 using ANTs..."

# Check if T1_HDbet exists
if [ -f "${SUBJECT_NAME}_desc-hdbet_T1w.nii.gz" ]; then
    
    # Step 9b-i: Register T1 to MNI using ANTs
    # run if file does not exist
    if [ ! -f "T1_to_MNI_Warped.nii.gz" ]; then
         echo "  Registering T1 to MNI..."
        antsRegistrationSyNQuick.sh -d 3 \
            -f "$MNI_TEMPLATE" \
            -m "${SUBJECT_NAME}_desc-hdbet_T1w.nii.gz" \
            -o T1_to_MNI_ \
            -t a
        
    else
        echo "  T1 to MNI registration already exists, skipping."
    fi
    
    # Step 8b-ii: Register mean_b0 to T1 using ANTs (rigid)
    # run if file does not exist
    if [ ! -f "b0_to_T1_0GenericAffine.mat" ]; then
        
        echo "  Registering b0 to T1..."
        antsRegistrationSyNQuick.sh -d 3 \
            -f "${SUBJECT_NAME}_desc-hdbet_T1w.nii.gz" \
            -m mean_b0_final.nii.gz \
            -o b0_to_T1_ \
            -t r
    else
        echo "  b0 to T1 registration already exists, skipping."
    fi  
    
    # Step 9b-iii: Apply combined transforms to FA
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
    echo "  WARNING: ${SUBJECT_NAME}_desc-hdbet_T1w.nii.gz not found. Skipping ANTs via T1 option."
fi

echo ""
echo "Quality check files created:"
echo "  - mean_b0_in_MNI.nii.gz (check b0-MNI alignment)"
echo "  - FA_in_MNI_direct.nii (OPTION A: direct b0->MNI)"
echo "  - FA_in_MNI_via_T1.nii (OPTION B: via T1 using ANTs)"

echo ""
echo "=========================================="
echo "Subject $SUBJECT_NAME processing complete!"
echo "End time: $(date)"
echo "FA maps in MNI space:"
echo "  Option A (direct): $DWI_DIR/FA_in_MNI_direct.nii"
echo "  Option B (via T1): $DWI_DIR/FA_in_MNI_via_T1.nii"
echo "=========================================="
