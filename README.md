# Tractography Pipeline

## Data and resource paths

Pipeline launchers take the BIDS dataset directory as their only positional
argument. They resolve it to an absolute path, discover `sub-*/ses-*`
directories, and submit each session job with that session's absolute
directory. Jobs do not rediscover the dataset or load shared path configuration.

For example:

```bash
bash scripts/2_preprocessing/1_submits_all_subs_preproc.sh /data/my_study/bids
bash scripts/3_to_6_ss3t.sh /data/my_study/bids
```

The cohort-level response averaging job is the exception: it receives the BIDS
root because it reads responses from all subjects:

```bash
bash scripts/3_deconvolution/2_responsemean.sh /data/my_study/bids
```

Repository-owned resources are resolved relative to the launcher location.
Launchers explicitly export that repository path to the few Slurm jobs that
need repository resources, because Slurm executes a transferred copy of a batch
script. These resources include `templates_parcellations/` and
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

The raw-DICOM directory may contain one ZIP archive or one decompressed
directory per subject. The archive or directory name is used as the subject
label (for example, `LP464.zip`, `LP464/`, or `sub-LP464/`).

After conversion, organize every subject into a session directory. The default
is `ses-1`; use `--session-label 4`, for example, when the acquisition belongs
to another session:

```bash
python3 scripts/1_before_preprocessing/2_organize_dcm2bids_helper.py \
    /data/my_study/conversion --apply
```

Input files use standard BIDS names. Each session must provide one
`sub-<label>_T1w.nii.gz` under `sub-<label>/ses-<label>/anat/` and one matching
`sub-<label>_dwi.nii.gz`, `.json`, `.bval`, and `.bvec` set under the session's
`dwi/` directory.
Additional filename entities such as `acq-` and `run-` are accepted, but the
current pipeline processes the first matching T1w and DWI series for each
session.

Processing filenames are derived by each stage from the subject label and the
pipeline's naming convention. They are local script variables, not environment
settings that users must configure.

Anatomical inputs remain under each session's `anat/`. Diffusion processing,
registration, tractography, and connectome products are written under its
`dwi/`. FreeSurfer outputs use `<sub>_<ses>` directories inside
`FREESURFER_SUBJECTS_DIR` so sessions cannot overwrite each other.

The preprocessing script reads `PhaseEncodingDirection` and `TotalReadoutTime`
from each DWI JSON sidecar.

## More Explanations

Each folder of the pipeline contains README files that explain the usage of the scripts as well as QC steps through visualization
for this be sure to have MRtrix installed or loaded locally

```bash
module load MRtrix
```

## Cleaning intermediate files

After the relevant quality-control checks, preview intermediate files that are
not needed by later stages:

```bash
bash scripts/cleanup_intermediates.sh --dry-run /data/my_study/bids
```

Run without `--dry-run` and type `delete` to confirm. Use `--stage 2,3`, for
example, to clean selected completed stages. QC-only products are retained by
default; add `--include-qc` only after reviewing them. Raw BIDS inputs and final
or downstream analysis products are always preserved.

## Preparing HCP Recommended data

Prepare HCP Recommended products in a separate processing dataset. The
preparation reads the original products under `sourcedata/hcp/`, so both older
subject-level layouts and newer session-level organized layouts work. It copies
selected inputs independently, validates their geometry and gradients, converts
DWI and the supplied diffusion mask to MRtrix, and calculates the final mean b=0.

For one subject:

```bash
bash scripts/2_preprocessing/prepare_hcp_for_processing.sh \
    /data/hcp-bids /data/hcp-prepared-test --subject sub-100307

OUTPUT_DIR=/data/hcp-prepared-test/slurm_logs \
FREESURFER_SUBJECTS_DIR=/data/hcp-prepared-test/freesurfer \
    bash scripts/3_to_6_msmt.sh /data/hcp-prepared-test
```

The preparation requires MRtrix and Python 3 with NumPy and NiBabel. Omit
`--subject` to prepare all subjects; use a dedicated output directory for the
single-subject trial so response averaging and job submission include only that
subject. The prepared output must be accessible to the Slurm compute nodes;
the source dataset is no longer needed by those jobs.

HCP diffusion is already registered to ACPC T1w coordinates. Preparation writes
`rigid_T1toDWI.txt` as an identity in MRtrix physical coordinates and records why
in its JSON sidecar. It retains the 0.7 mm T1 and anatomical mask for tissue
segmentation, and uses HCP's supplied 1.25 mm T1 for diffusion-grid QC. The
legacy `desc-resampled_bet.mif` filename contains HCP's supplied diffusion mask;
neither BET nor HD-BET is rerun. Do not run the DoC preprocessing launcher on
this prepared derivative dataset.

Stages 3--6 still calculate responses, FODs, 5TT/GMWMI, tractography, SIFT2,
FreeSurfer reconstruction, and the Schaefer connectome. A one-subject response
mean is for the trial; before cohort analysis, estimate the response mean from
the intended HCP cohort in a separate processing dataset.

Parcellation now writes `<sub>_atlas-<atlas>_space-dwi_parcels.nii.gz` under
`dwi/` and uses it for endpoint assignment. Existing completed DoC connectomes
retain their normal skip behavior; compare any recomputed DoC connectomes
separately because the parcel-alignment correction can change assignments.

For QC commands and the preparation regression checks, see
`scripts/2_preprocessing/README.md`.
