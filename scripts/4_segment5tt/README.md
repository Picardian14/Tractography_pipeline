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

| Substep | Inputs | Processing | Outputs |
| --- | --- | --- | --- |
| 1. Five-tissue segmentation | `../anat/<sub>_*_T1w.nii.gz` | Convert T1w to MRtrix and run `5ttgen fsl` | `<sub>_T1w.mif`, `<sub>_desc-nocoreg_5tt.mif` |
| 2. Registration reference | `<sub>_desc-preproc_dwi.mif` | Extract and average b=0 volumes | `<sub>_desc-mean_b0.mif`, `<sub>_desc-mean_b0.nii.gz` |
| 3. Rigid T1-to-DWI registration | Unregistered 5TT volume 0 and mean b=0 | FLIRT rigid registration and MRtrix transform conversion | `<sub>_desc-nocoreg_5tt.nii.gz`, `<sub>_desc-nocoreg_5tt_vol0.nii.gz`, `<sub>_from-T1w_to-dwi_rigid.mat`, `.txt` |
| 4. ACT images | Full 5TT and rigid transform | Transform the 5TT into diffusion coordinates while retaining its anatomical grid; derive the GM–WM interface | `<sub>_desc-coreg_5tt.nii.gz`, `<sub>_desc-coreg_5tt.mif`, `<sub>_desc-coreg_gmwmi.mif` |

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
