# Surface cortex with registered volumetric subcortex

`parcellate_cortico_subcortical_job.sh` creates a separate combined atlas and
SIFT2-weighted connectome. Defaults are **Schaefer 100 Yeo7 + Tian S2**, with
100 cortical nodes followed by 32 subcortical nodes. `MODEL=msmt` is the
default; use `MODEL=ss3t` for the corresponding existing tracks and weights.
The original cortical-only jobs remain available.

`2_run_parcellate_cortico_subcortical_jobs.sh` handles Slurm submission;
`parcellate_cortico_subcortical_job.sh` performs the processing for one session.

## Run on a completed subject

From the repository root on the cluster:

```bash
root="$PWD"
session="$root/outputs/hcp_single_subject/sub-100307/ses-1"
FREESURFER_SUBJECTS_DIR="$root/outputs/hcp_single_subject/freesurfer" \
MODEL=msmt bash scripts/6_parcellation/2_run_parcellate_cortico_subcortical_jobs.sh \
  "$session" --atlas schaefer100-yeo7 --subcortical-atlas tians2
```

To submit all sessions in a dataset, pass its BIDS root instead:

```bash
bash scripts/6_parcellation/2_run_parcellate_cortico_subcortical_jobs.sh \
  /absolute/path/to/bids --atlas schaefer100-yeo7 --subcortical-atlas tians2
```

The options are optional: this submitter defaults to `--atlas schaefer100-yeo7`
and `--subcortical-atlas tians2`. Change `--atlas` to another cortical atlas
folder. Command-line choices override `ATLAS_LABEL_NAME` and
`SUBCORTICAL_LABEL_NAME`; those environment variables remain supported.

To include this combined job at the end of a complete stage 3–6 workflow:

```bash
bash scripts/3_to_6_msmt.sh /absolute/path/to/bids \
  --atlas schaefer100-yeo7 --subcortical-atlas tians2
# The same options apply to scripts/3_to_6_ss3t.sh.
```

For stage 3–6, `--atlas` alone selects cortical-only parcellation, preserving
the existing workflow default. Supplying `--subcortical-atlas` selects this
combined job and passes the matching MSMT/SS3T model. The original dependencies
on tractography and FreeSurfer, and the workflow completion timing log, remain
in place.

The submit script creates `outputs/` and writes separate subject/session,
model and atlas-specific Slurm logs there. Set `OUTPUT_DIR` to change the log
directory. It submits one job for each `sub-*/ses-*` with a `dwi/` directory;
each job checks its processing inputs. Atlas settings and other exported
environment variables are passed to the processing job. The job requests
4 CPUs, 32 GB and 8 hours, including first-run subcortical registration.

The first run registers Tian to this subject. Later runs reuse
`anat/<sub>_atlas-tians2_space-T1w_labels.nii.gz`. **Change
`--atlas` to run another cortical atlas** with the same registered
subcortex. Both original flat atlas folders and the downloaded
`surface/fsaverage/` + `lut/` bundles are supported. Each bundle must have one
annotation per hemisphere, with corresponding input and output LUTs.

Required inputs are the completed FreeSurfer reconstruction of **the same
session's T1**, `anat/<sub>_T1w.nii.gz`, `dwi/rigid_T1toDWI.txt` in MRtrix
format, and the matching tractogram/SIFT2 weights. The FreeSurfer directory
must contain a working `fsaverage` link. Commands use the cluster's FreeSurfer
6, MRtrix, FSL and ANTs modules; Python is needed only for separate QC/tests.
Run one job per subject/combined atlas at a time: anatomical intermediates are
shared between MSMT and SS3T. Rerunning overwrites the combined outputs.

## Registration and merging

1. **Subcortex in subject space.** `register_subcortical_job.sh` reslices the
   FreeSurfer brain to the original native T1 grid, then registers the atlas's
   continuous anatomical template to that brain with full ANTs rigid, affine
   and nonlinear SyN registration. Fixed is subject T1; moving is template.
   It applies the forward warp followed by affine to the discrete atlas with
   nearest-neighbour interpolation, producing the native subcortical map
   **before merging**. Transforms, the warped template and registration inputs
   are retained in `anat/registration_<subcortical-atlas>/`.
2. **Surface cortex.** `mri_surf2surf` maps each `fsaverage` annotation onto
   the subject's registered cortical surface. `mri_aparc2aseg --ribbon`
   projects these labels into the subject's cortical ribbon. Only cortical
   source IDs present in the atlas's output LUT are retained; inherited aseg
   structures are excluded. This does not use an MNI cortical label volume.
3. **Native T1 merge.** Both label maps are placed on the original T1 grid
   with nearest-neighbour interpolation. The cortical output LUT defines
   ordering; cortical IDs are consecutive from 1. Subcortical IDs follow,
   ordered by their original source IDs. Definitions come from the full LUTs,
   so absent parcels never shift other node numbers. **Cortex wins at every
   overlap.** No dilation, CSF filling, or automatic clipping to aseg is applied.
4. **DWI coordinates.** The existing T1-to-DWI transform updates the merged
   image header. It retains the fine anatomical grid and unsigned integer
   labels rather than resampling onto coarse DWI voxels, which can remove
   small nuclei and thin cortical parcels. This image is in DWI physical
   coordinates but deliberately does not have the b0 voxel grid.
5. **Connectivity.** `tck2connectome` uses matching SIFT2 weights, a 4 mm
   radial endpoint search, symmetry and a zero diagonal. Weights are used
   directly without inverse-volume or maximum normalization. The search
   radius is an assignment rule, not a correction for misregistration.

The default Tian S2 **original 3T, 1 mm** atlas is MNI152NLin6Asym, paired
with FSL's `MNI152_T1_1mm_brain.nii.gz`. The downloaded `2009cAsym` alternative
must use its own matching template. Tian S1 and S3 can be selected with
`SUBCORTICAL_LABEL_NAME=tians1` or `tians3`. Atlas spaces are documented by
[Tian's authors](https://github.com/yetianmed/subcortex). See also the
[FreeSurfer ribbon projection documentation](https://surfer.nmr.mgh.harvard.edu/fswiki/fill%25annot%25volume)
and [ANTs transform ordering](https://github.com/ANTsX/ANTs/wiki/Forward-and-inverse-warps-for-warping-images%2C-pointsets-and-Jacobians).

## Reuse a previously registered subcortical parcellation

Set these variables before invoking the combined job:

```bash
SUBCORTICAL_LABEL_NAME=my_subcortex \
SUBCORTICAL_NATIVE=/absolute/path/to/subject_subcortex_in_T1w.nii.gz \
SUBCORTICAL_LUT=/absolute/path/to/subcortex_lut.txt \
ATLAS_LABEL_NAME=schaefer100-yeo7 \
bash scripts/6_parcellation/parcellate_cortico_subcortical_job.sh \
  /absolute/path/to/bids/sub-001/ses-1
```

The supplied volume must be a discrete, nonnegative label map already in
**this subject's native T1 scanner coordinates**. Matching voxel dimensions
alone do not establish registration. Reslicing changes its grid only; it does
not register another subject, MNI map, or DWI-space map to this T1. Its LUT
contains positive source IDs and names, either `ID name` or FreeSurfer-style
`ID name R G B A`. Zero is background. Two-column LUTs receive neutral display
colours; this does not affect label values or connectivity.

To register another template-space atlas first, set
`SUBCORTICAL_LABEL_NAME`, `SUBCORTICAL_ATLAS` and `SUBCORTICAL_TEMPLATE`, then
run `register_subcortical_job.sh SESSION_DIR`. A custom volume always requires
an explicit matching brain-extracted anatomical template. You can override
`SUBCORTICAL_NATIVE` to choose its output path.

Registration is reused by native-map filename. To change the source volume,
template, T1 or registration settings under the same atlas name, rerun the
registration script explicitly before merging. For the same inputs, the seed
defaults to 1; `NTHREADS` defaults to the Slurm allocation or 4. Numerical
registration results can still vary across tool versions and thread counts.

## Outputs and quality control

In `dwi/`, with `combined=schaefer100-yeo7-tians2`:

- `<sub>_atlas-<combined>_space-T1w_parcels.nii.gz` and
  `<sub>_atlas-<combined>_space-dwi_parcels.nii.gz`.
- `<sub>_atlas-<combined>_lut.txt` and `_nodes.tsv`, recording each combined
  node's name, tissue, source atlas and original label ID.
- `<sub>_model-<model>_atlas-<combined>_connectome.csv` and `_assignments.csv`.
- `parcellation/<combined>/`: separate cortical/subcortical maps, mapping LUTs
  and `inputs.tsv` identifying the registered subcortical input.

After processing, use a Python environment with NumPy and NiBabel:

```bash
python scripts/6_parcellation/qc_cortico_subcortical.py \
  /absolute/path/to/bids/sub-001/ses-1 schaefer100-yeo7-tians2 --model msmt
```

This checks discrete IDs, unknown subcortical labels, native grids, the exact
cortex-priority merge, preserved DWI labels and transform, matrix dimensions,
finite/nonnegative weights, symmetry and zero diagonal. It writes per-node
volumes and subcortical voxels removed at overlaps to `_qc_volumes.tsv`.
Missing parcels fail QC; their IDs remain in the node table. Processing does
not automatically run this separate QC command.

Inspect anatomical placement in addition to these numerical checks:

```bash
session=/absolute/path/to/bids/sub-001/ses-1
sub=$(basename "$(dirname "$session")")
combined=schaefer100-yeo7-tians2
work="$session/dwi/parcellation/$combined"
mrview "$session/anat/${sub}_T1w.nii.gz" \
  -overlay.load "$session/anat/registration_tians2/template_to_T1w_Warped.nii.gz" \
  -overlay.load "$work/cortex_space-T1w.nii.gz" \
  -overlay.load "$work/subcortex_space-T1w_labels.nii.gz"
mrview "$session/dwi/mean_b0_final.nii.gz" \
  -overlay.load "$session/dwi/${sub}_atlas-${combined}_space-dwi_parcels.nii.gz"
```

Check bilateral thalamus, caudate, putamen, pallidum, accumbens, hippocampus and
amygdala, the cortical ribbon, ventricular/CSF borders and DWI alignment.
Review overlap losses per nucleus. A large loss can indicate misregistration;
automatic dilation or masking could hide it. A group-derived atlas warped
onto individual anatomy does not establish subject-specific functional
subdivisions, and lesions or segmentation errors require particular review.
