#!/bin/bash

###############################################################################
# USER PATH MACRO
#
# Edit the values in this block for your installation. Every pipeline script
# sources this file. Any value can also be overridden before running a script,
# for example:
#   DATA_ROOT=/data/my_study bash scripts/3_deconvolution/2_responsemean.sh
###############################################################################
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DATA_ROOT="${DATA_ROOT:-${PIPELINE_ROOT}/data}"
BIDS_ROOT="${BIDS_ROOT:-${DATA_ROOT}}"
# Backwards-compatible alias. New scripts use BIDS_ROOT directly.
WORKBENCH_DIR="${WORKBENCH_DIR:-${BIDS_ROOT}}"
RAW_DICOM_DIR="${RAW_DICOM_DIR:-${DATA_ROOT}/raw_dicom}"
OUTPUT_DIR="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
ATLAS_ROOT="${ATLAS_ROOT:-${PIPELINE_ROOT}/atlas_data}"
FREESURFER_SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-${PIPELINE_ROOT}/freesurfer}"
MNI_TEMPLATE="${MNI_TEMPLATE:-${PIPELINE_ROOT}/MNI152_T1_2mm.nii.gz}"
SYNB0_SIF="${SYNB0_SIF:-${PIPELINE_ROOT}/synb0-disco_v3.0.sif}"
SIEMENS_ACQPARAMS="${SIEMENS_ACQPARAMS:-${BIDS_ROOT}/code/acqparams_siemens.txt}"
GE_ACQPARAMS="${GE_ACQPARAMS:-${BIDS_ROOT}/code/acqparams_GE.txt}"

export PIPELINE_ROOT DATA_ROOT BIDS_ROOT WORKBENCH_DIR RAW_DICOM_DIR OUTPUT_DIR
export ATLAS_ROOT FREESURFER_SUBJECTS_DIR MNI_TEMPLATE SYNB0_SIF
export SIEMENS_ACQPARAMS GE_ACQPARAMS
