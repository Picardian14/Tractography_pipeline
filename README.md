# Tractography Pipeline

## Data and resource paths

Pipeline launchers take the BIDS dataset directory as their only positional
argument. They resolve it to an absolute path, discover `sub-*` directories,
and submit each subject job with that subject's absolute directory. Subject
jobs do not rediscover the dataset or load shared path configuration.

For example:

```bash
bash scripts/2_preprocessing/1_submits_all_subs_preproc.sh /data/my_study/bids
bash scripts/3_to_6_msmt.sh /data/my_study/bids
```

The cohort-level response averaging job is the exception: it receives the BIDS
root because it reads responses from all subjects:

```bash
bash scripts/3_deconvolution/2_responsemean.sh /data/my_study/bids
```

Repository-owned resources are resolved relative to the launcher location.
Launchers explicitly export that repository path to the few Slurm jobs that
need repository resources, because Slurm executes a transferred copy of a batch
script. These resources include `atlas_data/`, `MNI152_T1_2mm.nii.gz`,
`images/diffusion_image.sif`, and `synb0-disco_v3.0.sif`. Slurm logs default to
`outputs/`, and FreeSurfer outputs default to `freesurfer/`, both at the
repository root. Existing advanced overrides such as `OUTPUT_DIR`,
`FREESURFER_SUBJECTS_DIR`, atlas labels, and alternate job-script variables
remain available where they are used.

DICOM conversion precedes creation of a BIDS dataset, so its launchers instead
take the raw-DICOM directory and conversion-output directory explicitly:

```bash
bash scripts/1_before_preprocessing/1_dcm2bids.sh \
    /data/my_study/raw_dicom /data/my_study/conversion
```

Input files use standard BIDS names. Each subject must provide one
`sub-<label>_T1w.nii.gz` under `anat/` and one matching
`sub-<label>_dwi.nii.gz`, `.json`, `.bval`, and `.bvec` set under `dwi/`.
Additional filename entities such as `acq-` and `run-` are accepted, but the
current pipeline processes the first matching T1w and DWI series for each
subject. Session directories (`sub-*/ses-*`) are not currently traversed.

Processing filenames are derived by each stage from the subject label and the
pipeline's naming convention. They are local script variables, not environment
settings that users must configure.

Anatomical inputs remain under `anat/`. Diffusion processing, registration,
tractography, and connectome products are written under `dwi/`. FreeSurfer
outputs remain in `FREESURFER_SUBJECTS_DIR`.

The preprocessing script reads `PhaseEncodingDirection` and `TotalReadoutTime`
from each DWI JSON sidecar.

## Preparing HCP Recommended data

After organizing HCP Recommended archives, prepare their reusable masks,
MRtrix inputs, mean-b0 images, and T1-to-DWI QC registrations before launching
stages 3--6:

```bash
bash scripts/hcp_recommended_to_bids.sh /data/hcp-zips /data/hcp-bids
bash scripts/2_preprocessing/prepare_hcp_for_processing.sh /data/hcp-bids
bash scripts/3_to_6_msmt.sh /data/hcp-bids
```

The preparation script uses the complete HCP products retained under
`sourcedata/hcp/`; it does not repeat HCP diffusion preprocessing.
