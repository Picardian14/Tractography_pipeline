# Stage 3: response estimation and deconvolution

Choose one model and keep it consistent in the later tractography and
parcellation stages:

- **SS3T** is for clinical data with only one shell.
- **MSMT-CSD** is for higher-quality, multi-shell data.

## Order of operations

### 1. Estimate each subject's response functions

```bash
bash scripts/3_deconvolution/1_run_dwi2resp_jobs.sh /path/to/bids
```

**Substep:** 1. Estimate each subject's response functions  
**Processing:** Convert the preprocessed DWI to MRtrix, resample the T1 mask to the DWI grid, and run `dwi2response dhollander`  
**Inputs:** `<sub>_desc-preproc_dwi.nii.gz`, `.bvec`, `.bval`; `../anat/<sub>_desc-hdbet_T1w_bet.nii.gz`  
**Outputs:** `<sub>_desc-preproc_dwi.mif`, `<sub>_desc-resampled_bet.mif`, `<sub>_desc-dhollander_response-{wm,gm,csf}.txt`, `<sub>_desc-dhollander_voxels.mif` in `<sub>/dwi/`

### 2. Average responses across subjects

**This step is essential: after responses have been calculated for every
subject, run `2_responsemean.sh` once before deconvolution.** Use one common set
of responses for subjects acquired with the same scanner and protocol. If
scanner/protocol groups differ, average them separately rather than mixing
them in the same BIDS root.

```bash
sbatch scripts/3_deconvolution/2_responsemean.sh /path/to/bids
```

The script reads every subject's individual WM, GM, and CSF response. It writes
`desc-meanDhollander_response-{wm,gm,csf}.txt` at the BIDS root and copies them
to each subject as
`<sub>_desc-meanDhollander_response-{wm,gm,csf}.txt`.

The common response sets the same FOD-amplitude scale across subjects; it does
not remove individual anatomical or connectivity differences.

### 3. Calculate and normalize FODs

For higher-quality multi-shell data:

```bash
bash scripts/3_deconvolution/3_do_msmt_csd.sh /path/to/bids
```

For clinical single-shell data:

```bash
bash scripts/3_deconvolution/3_do_ss3_tlocal.sh /path/to/bids
```

**Substep:** 3a. MSMT FOD calculation and normalization  
**Processing:** `dwi2fod msmt_csd`, tissue-volume concatenation, `mtnormalise`  
**Inputs:** Preprocessed DWI `.mif`, mean WM/GM/CSF responses, `<sub>_desc-resampled_bet.mif`  
**Outputs:** `<sub>_model-msmt_fod-{wm,gm,csf}.mif`, `<sub>_model-msmt_vf.mif`, `<sub>_model-msmt_desc-normalized_fod-{wm,gm,csf}.mif`

**Substep:** 3b. SS3T FOD calculation and normalization  
**Processing:** `ss3t_csd_beta1`, tissue-volume concatenation, `mtnormalise`  
**Inputs:** Preprocessed DWI `.mif`, mean WM/GM/CSF responses, `<sub>_desc-resampled_bet.mif`  
**Outputs:** `<sub>_model-ss3t_fod-{wm,gm,csf}.mif`, `<sub>_model-ss3t_vf.mif`, `<sub>_model-ss3t_desc-normalized_fod-{wm,gm,csf}.mif`

Both FOD routes use the same `<sub>_desc-resampled_bet.mif` mask.

## Visual quality control

Run the examples from one subject's `dwi/` directory. Set `model=ss3t` for
clinical single-shell data or `model=msmt` for higher-quality multi-shell data.

```bash
subject=sub-001
model=ss3t
```

Check the resampled mask on the preprocessed DWI in all three planes:

```bash
mrview "${subject}_desc-preproc_dwi.mif" \
  -overlay.load "${subject}_desc-resampled_bet.mif"
```

Inspect all volumes of the response-voxel image. WM, GM, and CSF selections
should fall in the corresponding tissues, and lesions should not dominate the
selection:

```bash
mrview "${subject}_desc-preproc_dwi.mif" \
  -overlay.load "${subject}_desc-dhollander_voxels.mif"
```

Inspect normalized WM FOD glyphs on the T1 registered to diffusion space. Zoom
into lesions and increase the glyph scale when necessary (approximately 3–4
was suggested in the preprocessing discussion):

```bash
mrview ../anat/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz \
  -plane 2 -size 2048,1024 -autoscale \
  -odf.load_sh "${subject}_model-${model}_desc-normalized_fod-wm.mif"
```

Also inspect the WM, GM, and CSF compartments together. Mixed tissue signals
inside a lesion can reflect pathology; off-brain FODs instead require checking
the mask and registration upstream.
