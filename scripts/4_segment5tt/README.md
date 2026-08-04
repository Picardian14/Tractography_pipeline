# Stage 4: 5TT segmentation and registration

This stage creates the anatomical constraints and GM–WM interface used by ACT
tractography. Its outputs are shared by both downstream routes:

- **SS3T** is for clinical data with only one shell.
- **MSMT-CSD** is for higher-quality, multi-shell data.

```bash
bash scripts/4_segment5tt/1_run_tissue_jobs.sh /path/to/bids
```

## Inputs, processing, and outputs

Jobs run in `<sub>/dwi/`.

**Substep:** 1. Five-tissue segmentation  
**Processing:** Convert T1w to MRtrix and run `5ttgen fsl`  
**Inputs:** `../anat/<sub>_*_T1w.nii.gz`  
**Outputs:** `<sub>_T1w.mif`, `<sub>_desc-nocoreg_5tt.mif`

**Substep:** 2. Registration reference  
**Processing:** Extract and average b=0 volumes (Step could be skipped if already calculated)
**Inputs:** `<sub>_desc-preproc_dwi.mif`  
**Outputs:** `mean_b0_final.mif`, `mean_b0_final.nii.gz`

**Substep:** 3. Rigid T1-to-DWI registration  
**Processing:** FLIRT rigid registration and MRtrix transform conversion  
**Inputs:** Unregistered 5TT volume 0 and mean b=0  
**Outputs:** `<sub>_desc-nocoreg_5tt.nii.gz`, `<sub>_desc-nocoreg_5tt_vol0.nii.gz`, `<sub>_from-T1w_to-dwi_rigid.mat`, `.txt`

**Substep:** 4. ACT images  
**Processing:** Transform the 5TT into diffusion coordinates while retaining its anatomical grid; derive the GM–WM interface  
**Inputs:** Full 5TT and rigid transform  
**Outputs:** `<sub>_desc-coreg_5tt.nii.gz`, `<sub>_desc-coreg_5tt.mif`, `<sub>_desc-coreg_gmwmi.mif`

## Visual quality control

Run these commands from one subject's `dwi/` directory, following the overlay
style in `check_images.sh`.

```bash
subject=sub-001
```

Compare the unregistered and registered 5TT images on the mean b=0:

```bash
mrview "${subject}_desc-mean_b0.mif" \
  -overlay.load "${subject}_desc-nocoreg_5tt.mif" \
  -overlay.load "${subject}_desc-coreg_5tt.mif"
```

Inspect the final 5TT and GMWMI in all three planes:

```bash
mrview "${subject}_desc-mean_b0.mif" \
  -overlay.load "${subject}_desc-coreg_5tt.mif" \
  -overlay.load "${subject}_desc-coreg_gmwmi.mif"
```

Verify that the registered 5TT follows the anatomy, the GM–WM boundary is
correct, lesions are represented plausibly, and the GMWMI follows the actual
GM–WM interface. A registration error here changes ACT seeding and streamline
termination.
