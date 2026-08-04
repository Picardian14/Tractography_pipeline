# Stage 6: cortical parcellation and connectome

This stage first runs FreeSurfer reconstruction, then maps the Schaefer atlas
to each subject and builds a SIFT2-weighted connectome. This step can be ran along the pre-processing step. (Takes 6H aprox)

Keep the connectome route consistent with deconvolution and tractography:

- **SS3T** is for clinical data with only one shell.
- **MSMT-CSD** is for higher-quality, multi-shell data.

## 1. FreeSurfer reconstruction

```bash
bash scripts/6_parcellation/1_run_recon_all_jobs.sh /path/to/bids
```
It is very important to setup properly here the FreeSurfers SUBJECTS_DIR path

**Substep:** 1. FreeSurfer reconstruction  
**Processing:** Run `recon-all -all` for each subject

**Inputs:**

- `anat/<sub>_*_T1w.nii.gz`: the subject's original anatomical T1w image.
- `images/diffusion_image.sif`: the container used to run FreeSurfer.
- `$FREESURFER_HOME/license.txt`: the FreeSurfer license mounted inside the
  container.

**Outputs:**

- `freesurfer/<sub>/`: the complete FreeSurfer subject directory containing
  the reconstructed surfaces, segmentations, and registration files.


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

**Inputs:**

- `freesurfer/<sub>/`.
- `templates_parcellations/schaefer100-yeo7/lh.schaefer100-yeo7.annot`: the
  left-hemisphere atlas annotation on `fsaverage`.
- `templates_parcellations/schaefer100-yeo7/rh.schaefer100-yeo7.annot`: the
  right-hemisphere atlas annotation on `fsaverage`.

**Outputs:**

- `freesurfer/<sub>/label/lh.schaefer100-yeo7.annot`: the atlas mapped to the
  subject's left cortical surface.
- `freesurfer/<sub>/label/rh.schaefer100-yeo7.annot`: the atlas mapped to the
  subject's right cortical surface.

**Substep:** 2.2. Label volume  
**Processing:** Create the anatomical parcellation and convert labels for MRtrix

**Inputs:**

- `freesurfer/<sub>/label/lh.schaefer100-yeo7.annot`.
- `freesurfer/<sub>/label/rh.schaefer100-yeo7.annot`.
- `LUT_schaefer100-yeo7.txt`: the lookup table for the input FreeSurfer labels.
- `LUT_schaefer100-yeo7_OUTPUT.txt`: the lookup table defining the output
  MRtrix parcel labels.

**Outputs:**

- `freesurfer/<sub>/mri/schaefer100-yeo7.mgz`: the subject's volumetric
  FreeSurfer parcellation.
- `freesurfer/<sub>/mri/schaefer100-yeo7.nii.gz`: the same parcellation in
  NIfTI format.
- `freesurfer/<sub>/mri/schaefer100-yeo7_parcels.nii.gz`: the label-converted
  parcels image used by `tck2connectome`.

**Substep:** 2.3. Connectome  
**Processing:** Run symmetric `tck2connectome` with zero diagonal and SIFT2 weights

**Inputs:**

- `<sub>_model-<model>_tractogram-10M.tck`: the full tractogram used to build
  the connectome.
- `<sub>_model-<model>_sift2-weights.txt`: the matching per-streamline SIFT2
  weights.
- `freesurfer/<sub>/mri/schaefer100-yeo7_parcels.nii.gz`.

**Outputs:**

- `<sub>_model-<model>_atlas-schaefer100-yeo7_connectome.csv`: the symmetric,
  SIFT2-weighted connectivity matrix with a zero diagonal.
- `<sub>_model-<model>_atlas-schaefer100-yeo7_assignments.csv`: the parcel-pair
  assignment for every streamline, written in `<sub>/dwi/`.

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
