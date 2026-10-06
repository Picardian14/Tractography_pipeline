# Stage 4: 5TT segmentation and registration

This stage creates the anatomical constraints and GM–WM interface used by ACT
tractography. Its outputs are shared by both downstream routes:

- **SS3T** is for clinical data with only one shell.
- **MSMT-CSD** is for higher-quality, multi-shell data.

```bash
bash scripts/4_segment5tt/1_run_tissue_jobs.sh /path/to/bids
```

## Inputs, processing, and outputs

Jobs run in `<sub>/<ses>/dwi/`.

**Substep:** 1. Five-tissue segmentation  
**Processing:** Convert T1w to MRtrix and run `5ttgen fsl`

**Inputs:**

- `../anat/<sub>_*_T1w.nii.gz`: the subject's original anatomical T1w image.
- For HCP preparation, the compatibility T1 contains the supplied 0.7 mm
  processed T1. Its `../anat/<sub>_space-T1w_desc-brain_mask.nii.gz` is passed to
  `5ttgen fsl -mask`, avoiding another brain extraction. DoC retains its existing
  FSL segmentation behavior when this optional supplied mask is absent.

**Outputs:**

- `<sub>_T1w.mif`: the T1w image converted to MRtrix format.
- `<sub>_desc-nocoreg_5tt.mif`: the five-tissue-type image in its original T1w
  coordinates. The volume - has the Grey Matter segmentation

**Substep:** 2. Registration reference  
**Processing:** Reuse the final mean b=0 produced during preprocessing or HCP
preparation; this job does not estimate another registration.

**Inputs:**

- `<sub>_desc-preproc_dwi.mif`: the final preprocessed DWI in MRtrix format.

**Outputs:**

- `mean_b0_final.mif`: the mean preprocessed b=0 image in MRtrix format.
- `mean_b0_final.nii.gz`: the same mean b=0 image in NIfTI format, used as the
  registration reference.

**Substep:** 3. T1-to-DWI mapping
**Processing:** Reuse the MRtrix mapping produced during preparation

**Inputs:**

- `rigid_T1toDWI.txt`: estimated for DoC; an explicit identity for the prepared
  HCP products already in T1w coordinates.
- `rigid_T1toDWI.mat`: optional FSL-format provenance for DoC.

**Outputs:**

- `<sub>_desc-nocoreg_5tt.nii.gz`: the unregistered 5TT image converted to
  NIfTI format.
- `<sub>_from-T1w_to-dwi_rigid.mat`: copied FSL matrix, when available.
- `<sub>_from-T1w_to-dwi_rigid.txt`: the copied MRtrix mapping.

**Substep:** 4. ACT images  
**Processing:** Transform the 5TT into diffusion coordinates while retaining its anatomical grid; derive the GM–WM interface

**Inputs:**

- `<sub>_desc-nocoreg_5tt.nii.gz`.
- `<sub>_from-T1w_to-dwi_rigid.txt`.

**Outputs:**

- `<sub>_desc-coreg_5tt.nii.gz`: the 5TT image positioned in diffusion
  coordinates while retaining its anatomical grid.
- `<sub>_desc-coreg_5tt.mif`: the registered 5TT image in MRtrix format for
  ACT.
- `<sub>_desc-coreg_gmwmi.mif`: the GM–WM interface image used to seed
  tractography.

## Cleaning intermediates

After Stage 4 completes, preview removable conversion and registration working
files with:

```bash
bash scripts/cleanup_intermediates.sh --stage 4 --dry-run /path/to/bids
```

The registered 5TT and GMWMI needed by tractography are retained. The
unregistered 5TT used for QC is retained unless `--include-qc` is supplied.

## Visual quality control

Run these commands from one session's `dwi/` directory, following the overlay
style in `check_images.sh`.

```bash
subject=sub-001
```

Compare the anatomical and diffusion-coordinate 5TT images on the mean b=0.
HCP's existing alignment means its identity transform produces no displacement:

```bash
mrview mean_b0_final.mif \
  -overlay.load "${subject}_desc-nocoreg_5tt.mif" \
  -overlay.load "${subject}_desc-coreg_5tt.mif"
```

Inspect the final 5TT and GMWMI in all three planes:

```bash
mrview mean_b0_final.mif \
  -overlay.load "${subject}_desc-coreg_5tt.mif" \
  -overlay.load "${subject}_desc-coreg_gmwmi.mif"
```

Verify that the registered 5TT follows the anatomy, the GM–WM boundary is
correct, lesions are represented plausibly, and the GMWMI follows the actual
GM–WM interface. A registration error here changes ACT seeding and streamline
termination.
