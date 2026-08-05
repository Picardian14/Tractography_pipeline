# Stage 5: ACT tractography and SIFT2

Use the launcher matching the deconvolution route:

- **SS3T** is for clinical data with only one shell.
- **MSMT-CSD** is for higher-quality, multi-shell data.

```bash
# Higher-quality multi-shell data
bash scripts/5_tractography/1_run_tckgen_msmt_jobs.sh /path/to/bids

# Clinical single-shell data
bash scripts/5_tractography/1_run_tckgen_ss3t_jobs.sh /path/to/bids
```

## Inputs, processing, and outputs

Jobs run in `<sub>/dwi/`. Replace `<model>` with `msmt` or `ss3t`.

**Substep:** 1. ACT tractography  
**Processing:** Generate 10 million streamlines with ACT, backtracking, and GMWMI seeding

**Inputs:**

- `<sub>_model-<model>_desc-normalized_fod-wm.mif`: the normalized
  white-matter FOD that supplies tracking directions.
- `<sub>_desc-coreg_5tt.mif`: the registered five-tissue-type image used by
  ACT to constrain streamlines.
- `<sub>_desc-coreg_gmwmi.mif`: the registered GM–WM interface used for
  seeding.

**Outputs:**

- `<sub>_model-<model>_tractogram-10M.tck`: the full tractogram containing 10
  million streamlines.

**Substep:** 2. QC subset  
**Processing:** Select 200,000 streamlines for visualization

**Inputs:**

- `<sub>_model-<model>_tractogram-10M.tck`.

**Outputs:**

- `<sub>_model-<model>_tractogram-200k.tck`: a smaller streamline subset used
  only for visual QC.

**Substep:** 3. SIFT2  
**Processing:** Calculate SIFT2 weights on the full tractogram

**Inputs:**

- `<sub>_model-<model>_tractogram-10M.tck`.
- `<sub>_model-<model>_desc-normalized_fod-wm.mif`.
- `<sub>_desc-coreg_5tt.mif`.

**Outputs:**

- `<sub>_model-<model>_sift2-weights.txt`: one SIFT2 weight for each streamline
  in the full tractogram.
- `<sub>_model-<model>_sift2-mu.txt`: the SIFT2 proportionality coefficient.
- `<sub>_model-<model>_sift2-coeffs.txt`: the coefficients from the SIFT2 fit.

The 200k tractogram is only for visual QC. Later connectome construction uses
the 10M tractogram and its matching SIFT2 weights.

## Visual quality control

From one subject's `dwi/` directory, inspect the smaller tractogram as in
`check_images.sh`:

```bash
subject=sub-001
model=ss3t # use msmt for the higher-quality multi-shell route
mrview ../anat/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz \
  -mode 2 -size 2048,1024 -autoscale \
  -tractography.load "${subject}_model-${model}_tractogram-200k.tck"
```

The tractogram should cover the main white matter and cortical gyri. Check for
streamlines outside the brain, crossing CSF or skull, missing corpus callosum,
or systematically noisy, fragmented, or sharp trajectories. If off-brain
streamlines are present, check the FOD mask, 5TT registration, GMWMI, and
distortion correction upstream.

Do not use weights from a different tractogram or from the 200k QC subset.
