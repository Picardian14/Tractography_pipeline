# Stage 2: preprocessing

This stage preprocesses one T1w image and one DWI series per BIDS subject. The
launcher submits one Slurm job per `sub-*` directory:

```bash
bash scripts/2_preprocessing/1_submits_all_subs_preproc.sh /path/to/bids
```

## Inputs and outputs

Each subject must contain:

- `anat/sub-*_T1w.nii.gz`: the subject's original anatomical T1w image.
- `dwi/sub-*_dwi.nii.gz`: the original diffusion-weighted image.
- `dwi/sub-*_dwi.json`: acquisition metadata; it must contain
  `PhaseEncodingDirection` (`j` or `j-`) and `TotalReadoutTime`.
- `dwi/sub-*_dwi.bval`: the b-value associated with each DWI volume.
- `dwi/sub-*_dwi.bvec`: the diffusion-gradient direction for each DWI volume.

The stage also uses:

- `images/diffusion_image.sif`: the container used to run HD-BET.
- `images/synb0-disco_v3.0.sif`: the container used for distortion estimation.
- `templates_parcellations/MNI152_T1_2mm.nii.gz`: the MNI registration
  reference.

Jobs run in each subject's `dwi/` directory. In the table below, `<sub>` is the
subject directory name, for example `sub-001`.

**Substep:** 1. T1 brain extraction  
**Processing:** HD-BET brain extraction. This tool uses Deep Learning to make an accurate anatomical T1. At order stages a mask is calculated directly on the diffusion to avoid resampling issues. 

**Inputs:**

- `../anat/<sub>_*_T1w.nii.gz`

**Outputs:**

- `../anat/<sub>_desc-hdbet_T1w.nii.gz`: the brain-extracted T1w image.
- `../anat/<sub>_desc-hdbet_T1w_bet.nii.gz`: the binary T1w brain mask.

**Substep:** 2. Denoising and Gibbs correction  
**Processing:** Convert to MRtrix, denoise with extent 7, calculate residuals, remove Gibbs ringing. Gibbs rings are the parallel shaded thick lines that appear in the image. The result of this cleaining can be observed in the QC steps described below

**Inputs:**

- Raw DWI file.
- Raw `.bval` file.
- Raw `.bvec` file.

**Outputs:**

- `Diff.mif`: the original DWI converted to MRtrix format with its gradients.
- `Diff_den.mif`: the denoised DWI.
- `noise.mif`: the noise estimate produced during denoising.
- `residual.mif`: the difference between the original and denoised DWI,
  used for QC.
- `Diff_den_gibbs.mif`: the denoised DWI after Gibbs-ringing correction.
- `Diff_den_gibbs.mif`: a link to `Diff_den_gibbs.mif` used by later
  commands.

**Substep:** 3. Synb0-DISCO preparation  
**Processing:** Create acquisition parameters, mean b=0, b=0 mask, and Synb0 inputs. Synb0 is a tool used in the next steps that requres specific Input setup, which is what is done in this step

**Inputs:**

- `Diff_den_gibbs.mif`
- DWI JSON file.
- Raw T1w file.

**Outputs:**

- `INPUTS/acqparams.txt`: phase-encoding and readout-time parameters for topup.
- `INPUTS/b0.nii.gz`: the mean b=0 image supplied to Synb0-DISCO.
- `INPUTS/T1.nii.gz`: the T1w image supplied to Synb0-DISCO.
- `mean_b0_AP.mif`: the mean AP b=0 image in MRtrix format, created for an AP
  acquisition.
- `mean_b0_AP.nii.gz`: the same AP mean b=0 image in NIfTI format.
- `mean_b0_PA.mif`: the mean PA b=0 image in MRtrix format, created for a PA
  acquisition.
- `mean_b0_PA.nii.gz`: the same PA mean b=0 image in NIfTI format.
- `<sub>_desc-preproc_b0_mask.nii.gz`: the b=0 brain mask used by eddy. This is done on the Diffusion itself instead of the T1

**Substep:** 4. Distortion estimation  
**Processing:** Run Synb0-DISCO/topup preparation. Here an artificial inverted B0 image will be created to calculate the TOPUP coefficients that will be used for eddy correction

**Inputs:**

- `INPUTS/`: the folder containing the acquisition parameters, b=0, and T1w
  inputs prepared in substep 3.

**Outputs:**

- `OUTPUTS/topup_fieldcoef.nii.gz`: the estimated susceptibility-distortion
  field coefficients.
- `OUTPUTS/topup*`: the remaining topup outputs used by eddy.

**Substep:** 5–6. Eddy preparation and correction  
**Processing:** Create eddy index/input files; correct motion, distortion, and gradients. Check Phase Encoding Direction distortion for more info on this

**Inputs:**

- `Diff_den_gibbs.mif` or `Diff.mif`.
- `INPUTS/acqparams.txt`.
- `<sub>_desc-preproc_b0_mask.nii.gz`.
- `OUTPUTS/topup*`.

**Outputs:**

- `eddy_indices.txt`: maps each DWI volume to its acquisition-parameter row.
- `Diff_eddy_in.nii.gz`: the DWI converted to NIfTI for eddy.
- `eddy_unwarped_images.nii.gz`: the motion- and distortion-corrected DWI.
- `eddy_unwarped_images.eddy_rotated_bvecs`: gradient directions rotated by
  eddy to match the corrected data.
- `eddy_unwarped_images.eddy_outlier_map`: eddy's slice-outlier map.
- `percentageOutliers.txt`: the calculated percentage of outlier slices.
- `Diff_preproc.mif`: the eddy-corrected DWI converted back to MRtrix format.
- `../anat/<sub>_desc-hdbet_T1w_bet.mif`: the T1w brain mask converted to
  MRtrix format.

**Substep:** 7. Bias correction and final export  
**Processing:** ANTs bias-field correction and gradient export. Bias field corrections removes imhomogeneities in brighness. If this step worstens the image you can skip it. 

**Inputs:**

- `Diff_preproc.mif`

**Outputs:**

- `Diff_preproc_unbiased.mif`: the DWI after bias-field correction.
- `bias.mif`: the estimated intensity bias field.
- `<sub>_desc-preproc_dwi.mif`: the final preprocessed DWI in MRtrix format.
- `<sub>_desc-preproc_dwi.nii.gz`: the final preprocessed DWI in NIfTI format.
- `<sub>_desc-preproc_dwi.bval`: the final exported b-values.
- `<sub>_desc-preproc_dwi.bvec`: the final exported, rotated gradient
  directions.

**Substep:** 8. DTI/FA  
**Processing:** Fit the tensor and calculate FA

**Inputs:**

- `<sub>_desc-preproc_dwi.mif`.
- `../anat/<sub>_desc-hdbet_T1w_bet.mif`.

**Outputs:**

- `<sub>_model-dti_tensor.mif`: the fitted diffusion-tensor image.
- `<sub>_model-dti_FA.mif`: the fractional-anisotropy map in MRtrix format.
- `<sub>_model-dti_FA.nii.gz`: the fractional-anisotropy map in NIfTI format.

**Substep:** 9. Registration/QC images  
**Processing:** Direct b=0-to-MNI registration, FA-to-MNI via T1, and rigid T1-to-DWI registration

**Inputs:**

- `<sub>_desc-preproc_dwi.mif`.
- `<sub>_model-dti_FA.nii.gz`.
- `../anat/<sub>_desc-hdbet_T1w.nii.gz`.
- `templates_parcellations/MNI152_T1_2mm.nii.gz`.

**Outputs:**

- `mean_b0_final.mif`: the final mean b=0 reference image in MRtrix format.
- `mean_b0_final.nii.gz`: the final mean b=0 reference image in NIfTI format.
- `mean_b0_in_MNI.nii.gz`: the mean b=0 transformed to MNI space.
- `FA_in_MNI_direct.nii`: FA transformed directly from DWI to MNI space.
- `FA_in_MNI_via_T1.nii`: FA transformed to MNI space through the T1w
  registration.
- `b02standard.mat`: the direct b=0-to-MNI transform.
- `T1_to_MNI_0GenericAffine.mat`: the affine T1w-to-MNI transform.
- `T1_to_MNI_Warped.nii.gz`: the T1w image transformed to MNI space for QC.
- `b0_to_T1_0GenericAffine.mat`: the rigid b=0-to-T1w transform.
- `rigid_T1toDWI.mat` and `.txt`: the rigid T1w-to-DWI transform in FSL and
  MRtrix formats.
- `../anat/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz`: the T1w image positioned in
  diffusion coordinates for QC and later overlays.

The T1-to-DWI transform maps the anatomical image into diffusion coordinates
without reslicing it to the lower-resolution DWI grid.

## Visual quality control


```bash
subject=sub-001
```

* Inspect several b=0 and diffusion-weighted volumes. Anatomical structure in the
denoising residuals can indicate removal of real signal:

```bash
mrview residual.mif
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
