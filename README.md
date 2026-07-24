# Tractography Pipeline

## Configure file and data paths

All shell scripts load the shared path macro in
[`scripts/paths_config.sh`](scripts/paths_config.sh). Before running the
pipeline on a new system, edit the `USER PATH MACRO` block in that file.

The defaults keep code-owned resources relative to the repository and expect
study data under `data/`. The main settings are:

- `PIPELINE_ROOT`: this repository
- `DATA_ROOT`: parent directory for study data
- `BIDS_ROOT`: BIDS dataset containing `sub-*/anat` and `sub-*/dwi`
- `RAW_DICOM_DIR`: input DICOM ZIP files
- `OUTPUT_DIR`: Slurm logs
- `ATLAS_ROOT`: atlas files
- `FREESURFER_SUBJECTS_DIR`: FreeSurfer outputs
- `MNI_TEMPLATE`, `SYNB0_SIF`, and scanner acquisition-parameter files

Settings can be overridden for one command without editing the file:

```bash
DATA_ROOT=/data/my_study \
BIDS_ROOT=/data/my_study/bids \
bash scripts/3_deconvolution/2_responsemean.sh
```

Input files use standard BIDS names. Each subject must provide one
`sub-<label>_T1w.nii.gz` under `anat/` and one matching
`sub-<label>_dwi.nii.gz`, `.bval`, and `.bvec` set under `dwi/`. Additional
BIDS entities such as `ses-`, `acq-`, and `run-` are accepted, but the current
pipeline processes the first matching T1w and DWI series for each subject.

Anatomical inputs remain under `anat/`. Diffusion processing, registration,
tractography, and connectome products are written under `dwi/`. FreeSurfer
outputs remain in `FREESURFER_SUBJECTS_DIR`.

Set `SCANNER_TYPE=GE` or `SCANNER_TYPE=siemens` when submitting preprocessing
jobs. It defaults to `GE`.
