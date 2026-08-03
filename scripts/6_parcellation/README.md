# Stage 6: cortical parcellation and connectome

This stage first runs FreeSurfer reconstruction, then maps the Schaefer atlas
to each subject and builds a SIFT2-weighted connectome.

Keep the connectome route consistent with deconvolution and tractography:

- **SS3T** is for clinical data with only one shell.
- **MSMT-CSD** is for higher-quality, multi-shell data.

## 1. FreeSurfer reconstruction

```bash
bash scripts/6_parcellation/1_run_recon_all_jobs.sh /path/to/bids
```

**Substep:** 1. FreeSurfer reconstruction  
**Processing:** Run `recon-all -all` for each subject  
**Inputs:** `anat/<sub>_*_T1w.nii.gz`, repository Singularity image, FreeSurfer license  
**Outputs:** Full FreeSurfer subject directory at `freesurfer/<sub>/` by default


## 2. Parcellation and connectome

The default atlas is `templates_parcellations/schaefer100-yeo7/`. It provides
the left/right `schaefer100-yeo7` annotations and input/output lookup tables.

```bash
# Higher-quality multi-shell data
bash scripts/6_parcellation/2_run_parcellate_msmt_jobs.sh /path/to/bids

# Clinical single-shell data
bash scripts/6_parcellation/2_run_parcellate_ss3t_jobs.sh /path/to/bids
```

**Substep:** 2.1. Surface atlas mapping  
**Processing:** Map each `fsaverage` hemisphere annotation to the subject  
**Inputs:** `freesurfer/<sub>/`, atlas `.annot` files  
**Outputs:** `freesurfer/<sub>/label/{lh,rh}.schaefer100-yeo7.annot`

**Substep:** 2.2. Label volume  
**Processing:** Create the anatomical parcellation and convert labels for MRtrix  
**Inputs:** Subject annotations and atlas lookup tables  
**Outputs:** `freesurfer/<sub>/mri/schaefer100-yeo7.mgz`, `.nii.gz`, and `_parcels.nii.gz`

**Substep:** 2.3. Connectome  
**Processing:** Run symmetric `tck2connectome` with zero diagonal and SIFT2 weights  
**Inputs:** `<sub>_model-<model>_tractogram-10M.tck`, matching SIFT2 weights, parcels image  
**Outputs:** `<sub>_model-<model>_atlas-schaefer100-yeo7_connectome.csv`, `..._assignments.csv` in `<sub>/dwi/`

The script uses the SIFT2 weights directly. It does not apply inverse-node-
volume scaling or per-subject maximum normalization.

## Visual quality control

From `<sub>/dwi/`, set the repository path and overlay the parcels on the T1
registered to diffusion space, following `check_images.sh`:

```bash
PIPELINE_ROOT=/path/to/Tractography_pipeline
subject=sub-001
mrview ../anat/${SUBJECT_NAME}_T1_in_dwi_space.nii.gz \
  -plane 2 -size 2048,1024 -autoscale \
  -overlay.load "$PIPELINE_ROOT/freesurfer/$subject/mri/schaefer100-yeo7_parcels.nii.gz"
```

Check that cortical labels follow the subject's cortex, no large parcels are
missing, and labels are not displaced relative to the GM–WM interface. Lesions
can make FreeSurfer surfaces and atlas nodes anatomically misleading; subjects
with massive lesions therefore need explicit review.

Also confirm before interpreting the matrix that the SIFT2 weight count matches
the 10M tractogram, as described in the stage 5 README.
