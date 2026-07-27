#!/bin/bash

###############################################################################
# USER PATH MACRO
#
# This is assuming a simple file structure where you have everything thrown in a main pipeline folder
###############################################################################
#####
# Pipeline root is where everything is. It is set as the folder above where the scripts are
#####
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
#####
# BIDS ROOT is where the BIDS dataset is located. It is set as a subfolder of PIPELINE_ROOT by default.
# I recommend you put this in /cohen/data and make a soft link in this folder. 
#####
BIDS_ROOT="${BIDS_ROOT:-${PIPELINE_ROOT}/data/}" # BIDS root is where the BIDS dataset is located.

# Backwards-compatible alias. New scripts use BIDS_ROOT directly.
RAW_DICOM_DIR="${RAW_DICOM_DIR:-${PIPELINE_ROOT}/raw_dicom}"
OUTPUT_DIR="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}" # for Logging the cluster outputs
ATLAS_ROOT="${ATLAS_ROOT:-${PIPELINE_ROOT}/atlas_data}" # to keep parcellation files
FREESURFER_SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-${PIPELINE_ROOT}/freesurfer}" # outputs from recon-all
MNI_TEMPLATE="${MNI_TEMPLATE:-${PIPELINE_ROOT}/MNI152_T1_2mm.nii.gz}" # MNI template for registration
SYNB0_SIF="${SYNB0_SIF:-${PIPELINE_ROOT}/synb0-disco_v3.0.sif}" # Singularity image for synb0-disco to do reverse phase encoding distortion correction
SIEMENS_ACQPARAMS="${SIEMENS_ACQPARAMS:-${PIPELINE_ROOT}/acqparams_siemens.txt}" # this are the parameters neccesary for Eddy
GE_ACQPARAMS="${GE_ACQPARAMS:-${PIPELINE_ROOT}/acqparams_GE.txt}" # They are scanner specific. 

export PIPELINE_ROOT DATA_ROOT BIDS_ROOT WORKBENCH_DIR RAW_DICOM_DIR OUTPUT_DIR
export ATLAS_ROOT FREESURFER_SUBJECTS_DIR MNI_TEMPLATE SYNB0_SIF
export SIEMENS_ACQPARAMS GE_ACQPARAMS
