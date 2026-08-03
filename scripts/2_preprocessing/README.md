# Stage 2: preprocessing

This stage preprocesses one T1w image and one DWI series per BIDS subject. The
launcher submits one Slurm job per `sub-*` directory:

```bash
bash scripts/2_preprocessing/1_submits_all_subs_preproc.sh /path/to/bids
```

## Inputs and outputs

Each subject must contain:

- `anat/sub-*_T1w.nii.gz`
- `dwi/sub-*_dwi.nii.gz` and matching `.json`, `.bval`, and `.bvec` files
- `PhaseEncodingDirection` (`j` or `j-`) and `TotalReadoutTime` in the DWI JSON

The stage also uses `images/diffusion_image.sif`,
`images/synb0-disco_v3.0.sif`, and
`templates_parcellations/MNI152_T1_2mm.nii.gz` from this repository.

Jobs run in each subject's `dwi/` directory. In the table below, `<sub>` is the
subject directory name, for example `sub-001`.

**Substep:** 1. T1 brain extraction  
**Processing:** HD-BET brain extraction  
**Inputs:** `../anat/<sub>_*_T1w.nii.gz`  
**Outputs:** `../anat/<sub>_desc-hdbet_T1w.nii.gz`, `../anat/<sub>_desc-hdbet_T1w_bet.nii.gz`

**Substep:** 2. Denoising and Gibbs correction  
**Processing:** Convert to MRtrix, denoise with extent 7, calculate residuals, remove Gibbs ringing  
**Inputs:** Raw DWI, `.bval`, `.bvec`  
**Outputs:** `Diff.mif`, `Diff_den_ext7.mif`, `noise_ext7.mif`, `residual_ext7.mif`, `Diff_den_gibbs_ext7.mif`, `Diff_den_gibbs.mif`

**Substep:** 3. Synb0-DISCO preparation  
**Processing:** Create acquisition parameters, mean b=0, b=0 mask, and Synb0 inputs  
**Inputs:** Corrected DWI, DWI JSON, raw T1w  
**Outputs:** `INPUTS/acqparams.txt`, `INPUTS/b0.nii.gz`, `INPUTS/T1.nii.gz`, `mean_b0_AP.*` or `mean_b0_PA.*`, `<sub>_desc-preproc_b0_mask.nii.gz`

**Substep:** 4. Distortion estimation  
**Processing:** Run Synb0-DISCO/topup preparation  
**Inputs:** `INPUTS/`  
**Outputs:** `OUTPUTS/`, including `OUTPUTS/topup_fieldcoef.nii.gz` and the `OUTPUTS/topup` files used by eddy

**Substep:** 5–6. Eddy preparation and correction  
**Processing:** Create eddy index/input files; correct motion, distortion, and gradients  
**Inputs:** DWI, acquisition parameters, b=0 mask, topup outputs  
**Outputs:** `eddy_indices.txt`, `Diff_eddy_in.nii.gz`, `eddy_unwarped_images.nii.gz`, `eddy_unwarped_images.eddy_rotated_bvecs`, eddy QC files, `percentageOutliers.txt`, `Diff_preproc.mif`

**Substep:** 7. Bias correction and final export  
**Processing:** ANTs bias-field correction and gradient export  
**Inputs:** `Diff_preproc.mif`  
**Outputs:** `Diff_preproc_unbiased.mif`, `bias.mif`, `<sub>_desc-preproc_dwi.mif`, `.nii.gz`, `.bval`, and `.bvec`

**Substep:** 8. DTI/FA  
**Processing:** Fit the tensor and calculate FA  
**Inputs:** Preprocessed DWI and T1 mask  
**Outputs:** `<sub>_model-dti_tensor.mif`, `<sub>_model-dti_FA.mif`, `<sub>_model-dti_FA.nii.gz`

**Substep:** 9. Registration/QC images  
**Processing:** Direct b=0-to-MNI registration, FA-to-MNI via T1, and rigid T1-to-DWI registration  
**Inputs:** Mean b=0, FA, brain-extracted T1w, MNI template  
**Outputs:** `mean_b0_final.*`, `mean_b0_in_MNI.nii.gz`, `FA_in_MNI_direct.nii`, `FA_in_MNI_via_T1.nii`, registration transforms, `../anat/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz`

The T1-to-DWI transform maps the anatomical image into diffusion coordinates
without reslicing it to the lower-resolution DWI grid.


```bash
bash scripts/2_preprocessing/prepare_hcp_for_processing.sh /path/to/hcp-bids
```

## Visual quality control


```bash
subject=sub-001
```

* Inspect several b=0 and diffusion-weighted volumes. Anatomical structure in the
denoising residuals can indicate removal of real signal:

```bash
mrview Diff.mif -overlay.load residual_ext7.mif
```

* Overlay the b=0 mask in all three planes. Check that brain tissue is retained
and non-brain tissue is excluded, especially inferior frontal and temporal
regions, the cerebellum, and lesions:

```bash
mrview mean_b0_final.nii.gz \
  -overlay.load "${subject}_desc-preproc_b0_mask.nii.gz"
```

* Check distortion correction and rigid T1-to-DWI alignment. Inspect the outer
brain boundary, ventricles, corpus callosum, GM–WM interface, and lesion
boundaries:

```bash
mrview mean_b0_final.nii.gz \
  -overlay.load ../anat/T1_in_dwi_space.nii.gz \
  -overlay.threshold_max 60
```

Clear distortion-correction failure or severe T1–DWI misregistration will be
inherited by the later FOD, ACT, and parcellation steps.
