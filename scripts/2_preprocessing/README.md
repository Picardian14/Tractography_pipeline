# Stage 2: preprocessing

## Preparing already processed HCP data

HCP preparation is separate from the raw DoC preprocessing below. For a
single-subject trial, prepare a separate output directory:

```bash
bash scripts/2_preprocessing/prepare_hcp_for_processing.sh \
  /mnt/data1/HCP_YOUNG_ADULTS_UNRELATED_BIDS \
  /path/on/shared/filesystem/hcp_test --subject sub-100307

OUTPUT_DIR=/path/on/shared/filesystem/hcp_test/slurm_logs \
FREESURFER_SUBJECTS_DIR=/path/on/shared/filesystem/hcp_test/freesurfer \
  bash scripts/3_to_6_msmt.sh /path/on/shared/filesystem/hcp_test
```

The source must retain `sourcedata/hcp/sub-<label>/T1w/` from the Recommended
archives. Python 3, NumPy, NiBabel, and MRtrix are required. Outputs use
`sub-<label>/ses-1/` and contain independent copies of the selected HCP inputs.
They can be moved to another host without the source dataset. Rerunning
preparation verifies existing copies and reuses completed MRtrix outputs; an
input disagreement stops preparation instead of overwriting analysis inputs.

Geometry, gradient counts, and binary masks are checked before conversion.
The final diffusion mask is reused as `<sub>_desc-resampled_bet.mif`, the legacy
name consumed by CSD. The 0.7 mm anatomical mask is saved as
`anat/<sub>_space-T1w_desc-brain_mask.nii.gz`; tissue generation reuses it.
`rigid_T1toDWI.txt` contains an identity in MRtrix physical coordinates, with
provenance in `rigid_T1toDWI.json`, because HCP already registered diffusion to
ACPC T1w space. No additional DWI preprocessing or registration is performed.

From the prepared session's `dwi/` directory, inspect the inputs:

```bash
subject=sub-100307
mrview mean_b0_final.nii.gz \
  -overlay.load "${subject}_desc-resampled_bet.mif"
mrview mean_b0_final.nii.gz \
  -overlay.load "../anat/${subject}_T1_in_dwi_space.nii.gz"
```

After stages 4--6 finish, inspect the anatomical constraints and parcels:

```bash
mrview "../anat/${subject}_T1_in_dwi_space.nii.gz" \
  -overlay.load "${subject}_desc-coreg_5tt.mif" \
  -overlay.load "${subject}_desc-coreg_gmwmi.mif"
mrview "../anat/${subject}_T1_in_dwi_space.nii.gz" \
  -overlay.load "${subject}_atlas-schaefer100-yeo7_space-dwi_parcels.nii.gz"
```

Check the GM–WM interface, cortex, ventricles, cerebellum, and parcel boundaries
in all three planes. The scripts preserve anatomical tissue/parcel resolution;
the grids may differ while physical coordinates remain aligned. For HCP's
identity mapping, the tissue transform itself should produce no displacement.

Regression checks use small synthetic images and real MRtrix transformations,
with external segmentation/FreeSurfer/scheduler calls replaced by test stubs:

```bash
python3 -m unittest discover -s tests -v
```

## Raw DoC preprocessing

This stage preprocesses one T1w image and one DWI series per BIDS session. The
launcher submits one Slurm job per `sub-*/ses-*` directory:

```bash
bash scripts/2_preprocessing/1_submits_all_subs_preproc.sh /path/to/bids
```

### Choosing Synb0 or acquired reverse-PE B0 images

Synb0 is the default. Select the method with the optional second argument:

```bash
bash scripts/2_preprocessing/1_submits_all_subs_preproc.sh /path/to/bids synb0
bash scripts/2_preprocessing/1_submits_all_subs_preproc.sh /path/to/bids reversepe
```

For `reversepe`, the launcher looks for `dwi/*_acq-inverted*_b0.nii.gz` (the
organizer's output) or `fmap/*_epi.nii.gz`. Exactly one candidate with matching
JSON must exist in each session; sessions without this are skipped. The image
must be a B0-only image or series, with the opposite `j`/`j-` phase encoding
to the primary DWI. A different spatial grid is handled automatically: the
reverse mean B0 is resampled onto the primary DWI B0 grid using its scanner
coordinates and sinc interpolation. The acquired images are retained, and
`INPUTS/reverse_b0_native.nii.gz` preserves the mean on its original grid.
Both JSON files must supply their
own positive `TotalReadoutTime`. NumPy and NiBabel must be available to Python 3
for geometry checks. A supplied `.bval` is checked for B0-only content.
For odd DWI dimensions, TOPUP runs without spatial subsampling so a grid such
as `120 x 120 x 69` can be retained without cropping or padding the DWI.

To specify a reverse B0 stored elsewhere, submit one session explicitly:

```bash
sbatch --output=/path/to/logs/preproc-%j.out \
  --error=/path/to/logs/preproc-%j.err \
  scripts/2_preprocessing/preprocess_single_subject.sh \
  /path/to/bids/sub-001/ses-1 reversepe /path/to/reverse_b0.nii.gz
```

HD-BET and denoising are shared. From substep 3 onward, working files and
results are saved separately under:

```text
ses-1/dwi/preprocessing/synb0/
ses-1/dwi/preprocessing/reversepe/
```

After a successful run, the selected method's final DWI, gradients, masks,
tensor/FA, B0 references, and registration outputs overwrite the usual files
in `dwi/`; the matching registered T1 overwrites the usual file in `anat/`.
This includes `Diff_preproc.mif`, `Diff_preproc_unbiased.mif`, and
`<sub>_desc-preproc_dwi.*`. Filenames used by later stages stay unchanged.
The original converted `Diff.mif` remains the shared, uncorrected input.
`<sub>_desc-preprocessing_info.txt` records the active method. Saved method
outputs are independent copies and remain available for comparison.

Rerunning a method reuses its TOPUP and eddy results, then recreates and
activates the final outputs. Existing Stage 2 results from before this layout
are not imported; the first run computes a separate saved variant. If you
change the actual inputs for a method, use a fresh method folder. Do not
switch methods while later stages are running. Existing FODs, tractograms,
and connectomes are not regenerated or removed by preprocessing: preserve
earlier downstream results and clear their output files before rerunning
stages 3--6, because some stages otherwise skip existing outputs.

## Comparing FA between correction methods

Open [`validate_fa_distributions.ipynb`](validate_fa_distributions.ipynb) in
Jupyter and set the original reverse-PE and artificial-B0 FA image paths.
The example paths use the saved `preprocessing/reversepe/` and
`preprocessing/synb0/` results for one subject/session. The notebook requires
NumPy, NiBabel, Matplotlib, and SciPy.

Supply a common binary brain or white-matter NIfTI mask for the final
comparison. The notebook checks image grids, reports invalid values, and plots
normalized histograms, cumulative distributions, and a spatial difference
slice. It also reports distribution distances and paired FA errors. Matching
distributions alone do not establish spatial agreement or equivalence.

## Inputs and outputs

Each session must contain:

- `anat/sub-*_T1w.nii.gz`: the subject's original anatomical T1w image.
- `dwi/sub-*_dwi.nii.gz`: the original diffusion-weighted image.
- `dwi/sub-*_dwi.json`: acquisition metadata; it must contain
  `PhaseEncodingDirection` (`j` or `j-`) and `TotalReadoutTime`.
- `dwi/sub-*_dwi.bval`: the b-value associated with each DWI volume.
- `dwi/sub-*_dwi.bvec`: the diffusion-gradient direction for each DWI volume.

The stage also uses:

- `images/diffusion_image.sif`: the container used to run HD-BET.
- `images/synb0-disco_v3.0.sif`: distortion estimation for `synb0` only.
- `templates_parcellations/MNI152_T1_2mm.nii.gz`: the MNI registration
  reference.

Substeps 1--2 run in each session's `dwi/` directory; substeps 3--10 run in
`dwi/preprocessing/<method>/`. Relative output names below refer to those
working directories. Final outputs are also copied to their usual downstream
locations. `<sub>` is the subject directory name, for example `sub-001`.

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

**Substep:** 3. Distortion-correction preparation

**Processing:** Create acquisition parameters, mean b=0, and b=0 mask. For
`synb0`, also copy the anatomical input. For `reversepe`, average the acquired
reverse-PE B0 series and merge it with the primary DWI's mean B0.

**Inputs:**

- `Diff_den_gibbs.mif`
- DWI JSON file.
- Raw T1w file.

**Outputs:**

- `INPUTS/acqparams.txt`: phase-encoding and readout-time parameters for topup.
- `INPUTS/b0.nii.gz`: the mean b=0 image supplied to Synb0-DISCO.
- `INPUTS/T1.nii.gz`: the T1w image supplied to Synb0-DISCO.
- `mean_b0.mif`: the primary DWI's mean B0 in MRtrix format.
- `INPUTS/reverse_b0.nii.gz`: acquired reverse-PE mean B0 (`reversepe` only).
- `INPUTS/reverse_b0_native.nii.gz`: reverse-PE mean B0 before regridding.
- `INPUTS/b0_pair.nii.gz`: primary and reverse-PE mean B0s, in acquisition-row
  order (`reversepe` only).
- `<sub>_desc-preproc_b0_mask.nii.gz`: the b=0 brain mask used by eddy. This is done on the Diffusion itself instead of the T1

**Substep:** 4. Distortion estimation  
**Processing:** For `synb0`, run Synb0-DISCO, which synthesizes an undistorted
B0 reference and runs TOPUP. For `reversepe`, run TOPUP directly on the two
acquired mean B0s using `b02b0.cnf`. Both methods supply the resulting field
estimate to eddy; the DWI is not separately corrected with `applytopup`.

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

- Shared `dwi/Diff_den_gibbs.mif`, for both methods and both PE polarities.
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

**Substep:** 8. Final b=0 and T1-to-DWI mask registration

**Processing:** Calculate the final mean b=0, estimate the rigid T1-to-DWI
transform using the brain-extracted T1w image, and apply it to the HD-BET mask
on the final DWI grid with nearest-neighbour interpolation.

**Outputs:**

- `mean_b0_final.mif` and `mean_b0_final.nii.gz`: final DWI references.
- `rigid_T1toDWI.mat` and `.txt`: T1w-to-DWI rigid transforms.
- `<sub>_desc-resampled_bet.mif`: HD-BET mask registered to final DWI space.
- `../anat/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz`: registered T1w image for QC.

**Substep:** 9. DTI/FA

**Processing:** Fit the tensor inside the registered HD-BET mask and calculate FA.

**Inputs:**

- `<sub>_desc-preproc_dwi.mif`.
- `<sub>_desc-resampled_bet.mif`.

**Outputs:**

- `<sub>_model-dti_tensor.mif`: the fitted diffusion-tensor image.
- `<sub>_model-dti_FA.mif`: the fractional-anisotropy map in MRtrix format.
- `<sub>_model-dti_FA.nii.gz`: the fractional-anisotropy map in NIfTI format.

**Substep:** 10. Registration/QC images

**Processing:** Direct b=0-to-MNI registration and FA-to-MNI via T1.

**Inputs:**

- `<sub>_desc-preproc_dwi.mif`.
- `<sub>_model-dti_FA.nii.gz`.
- `../anat/<sub>_desc-hdbet_T1w.nii.gz`.
- `templates_parcellations/MNI152_T1_2mm.nii.gz`.

**Outputs:**

- `mean_b0_in_MNI.nii.gz`: the mean b=0 transformed to MNI space.
- `FA_in_MNI_direct.nii`: FA transformed directly from DWI to MNI space.
- `FA_in_MNI_via_T1.nii`: FA transformed to MNI space through the T1w
  registration.
- `b02standard.mat`: the direct b=0-to-MNI transform.
- `T1_to_MNI_0GenericAffine.mat`: the affine T1w-to-MNI transform.
- `T1_to_MNI_Warped.nii.gz`: the T1w image transformed to MNI space for QC.
- `b0_to_T1_0GenericAffine.mat`: the rigid b=0-to-T1w transform.

The registered HD-BET mask is explicitly resliced onto the final DWI grid so
that it can be used safely by tensor fitting, response estimation, CSD, and
intensity normalization.

## Cleaning intermediates

After preprocessing completes, preview removable Stage 2 working files with:

```bash
bash scripts/cleanup_intermediates.sh --stage 2 --dry-run /path/to/bids
```

The saved `dwi/preprocessing/` method folders are not touched by cleanup.
The final preprocessed DWI and gradients, masks, DTI/FA products, mean b=0,
anatomical derivatives, transforms, and registration images are retained. Add
`--include-qc` only after inspecting `noise.mif` and `residual.mif`.

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
  -overlay.load ../anat/${subject}_T1_in_dwi_space.nii.gz \
  -overlay.threshold_max 60
```

Clear distortion-correction failure or severe T1–DWI misregistration will be
inherited by the later FOD, ACT, and parcellation steps.
