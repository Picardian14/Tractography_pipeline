# Surface Schaefer + volumetric Tian parcellation

`parcellate_schaefer_tian_job.sh` is a separate variant of the existing
parcellation jobs. It creates combined cortical/subcortical nodes and rebuilds
the connectome using the existing tractogram and SIFT2 weights. It contains no
preflight validation, image QC, parcel-count checks, or QC-based stopping rules.
Commands stop on tool failures. Rerunning overwrites this variant's outputs and
repeats registration; the original cortical-only outputs are separate.

## Run

From the repository root, for one session:

```bash
MODEL=ss3t bash scripts/6_parcellation/parcellate_schaefer_tian_job.sh \
  /absolute/path/to/bids/sub-001/ses-1
```

For MSMT-CSD, use `MODEL=msmt`. The job changes neither tractography nor SIFT2;
`MODEL` selects the existing matching files.

For Slurm, the new job requests 4 CPUs, 32 GB, and 6 hours, including nonlinear
registration:

```bash
mkdir -p outputs
MODEL=msmt sbatch --job-name=parcellate-schaefer-tian-sub-001_ses-1 \
  --output=outputs/sub-001_ses-1-schaefer-tian-%j.out.txt \
  --error=outputs/sub-001_ses-1-schaefer-tian-%j.err.txt \
  scripts/6_parcellation/parcellate_schaefer_tian_job.sh \
  /absolute/path/to/bids/sub-001/ses-1
```

The session argument can also be relative; output paths are resolved internally.
Run one combined parcellation job at a time for a given session/atlas, since
SS3T and MSMT use the same anatomical intermediates and node images.

Required existing inputs:

- The FreeSurfer reconstruction of **this session's T1**, at
  `freesurfer/<sub>_<ses>/`, including `mri/brain.mgz` and cortical surfaces.
- `freesurfer/fsaverage`, as required by `mri_surf2surf`. If using a separate
  `FREESURFER_SUBJECTS_DIR`, set up its `fsaverage` reference beforehand.
- `anat/<sub>_T1w.nii.gz`: the same T1 used by recon-all and the existing
  T1-to-DWI registration.
- `dwi/rigid_T1toDWI.txt`, in **MRtrix format**, and
  `dwi/mean_b0_final.nii.gz`, from preprocessing/HCP preparation.
- `dwi/<sub>_model-<model>_tractogram-10M.tck` and matching
  `<sub>_model-<model>_sift2-weights.txt`.
- FreeSurfer 6, FSL, ANTs, and MRtrix through the same `ml` environment as the
  other jobs. No Python dependency is added to the processing job.

## Spatial operations and node numbering

1. Transfer Schaefer annotations from `fsaverage` with `mri_surf2surf`, then
   project them into the subject's volume with `mri_aparc2aseg`.
2. Extract only Schaefer cortical entries from its input LUT. `labelconvert`
   maps everything else, including inherited aseg subcortical structures, to
   zero. Cortical node IDs follow ascending FreeSurfer source IDs, left then
   right, and agree with the existing 100-parcel output LUT.
3. Resample the cortex and FreeSurfer brain to the original T1 grid using their
   scanner-coordinate headers. Cortex uses nearest neighbour; the brain's
   continuous intensities use linear interpolation. This handles conformation
   of the **same** anatomical acquisition; it does not register another
   session's FreeSurfer reconstruction to the current session.
4. Register the subject's brain to the subcortical atlas's anatomical template
   with `antsRegistrationSyN.sh -t s` (rigid, affine, nonlinear SyN). Apply the
   inverse affine and inverse warp to Tian, using the original T1 as the output
   grid and nearest-neighbour interpolation. The atlas label map itself is
   never used to fit an anatomical registration.
5. Remap subcortical IDs after the cortical IDs, then merge on the T1 grid.
   **Cortex takes priority at overlaps.** Subcortical nodes occupy remaining
   voxels; they are not additionally clipped to aseg.
6. Apply the existing T1-to-DWI transform once to the combined nodes, resampling
   onto `mean_b0_final.nii.gz` with nearest neighbour and unsigned integer output.
7. Run `tck2connectome` with the matching SIFT2 weights, a 4 mm radial endpoint
   search (the existing default, made explicit), symmetry, and a zero diagonal.

With the defaults, Schaefer occupies IDs **1–100** and Tian S1 IDs **101–116**.
Tian's original order is right hemisphere first, then left; do not assume its
order matches the cortical hemispheres. The included
`LUT_Tian_Subcortex_S1_3T.txt` records the original atlas IDs and region names.
Its display colours are local choices.

The original Tian 3T release uses **MNI152NLin6Asym**. The default registration
target is `$FSLDIR/data/standard/MNI152_T1_2mm_brain.nii.gz`, in that space.
The bundled `SchaeferTian_100_7_MNI_2mm_original.nii.gz` is not used: cortex
continues to come from the subject's surfaces. The preprocessing job's
`T1_to_MNI_` registration is affine-only and is not reused here.
See the [Tian atlas documentation](https://github.com/yetianmed/subcortex/blob/master/README.md)
and [ANTs inverse-transform conventions](https://github.com/ANTsX/ANTs/wiki/Forward-and-inverse-warps-for-warping-images,-pointsets-and-Jacobians).

Settings remain ordinary environment variables:

```bash
ATLAS_LABEL_NAME=schaefer200-yeo7 MODEL=ss3t \
  bash scripts/6_parcellation/parcellate_schaefer_tian_job.sh \
  /absolute/path/to/bids/sub-001/ses-1
```

This uses the corresponding annotations and `LUT_schaefer200-yeo7.txt`;
no pre-existing `_OUTPUT.txt` is needed. `PIPELINE_ROOT`,
`FREESURFER_SUBJECTS_DIR`, `ATLAS_ROOT`, `ATLAS_DIR`, and `TABLE_LABEL_NAME`
can also be overridden. `NTHREADS` defaults to the Slurm allocation or 4;
`ANTS_RANDOM_SEED` defaults to 1.

For another volumetric subcortical atlas, set **all four** of
`SUBCORTICAL_LABEL_NAME`, `SUBCORTICAL_ATLAS`, `SUBCORTICAL_LUT`, and
`SUBCORTICAL_TEMPLATE`. The template must match that atlas's physical space and
be a brain-extracted T1 image. The LUT uses FreeSurfer-style
`index name R G B A` rows with positive, unique IDs/names; zero is background.
Rows are sorted by source ID and assigned consecutive combined IDs. Hemisphere
metadata uses Tian's `-lh`/`-rh` name suffixes; other naming conventions produce
`NA` in that column without changing node labels.

## Outputs

In the session's `dwi/`, using the default combined atlas name
`schaefer100-yeo7-tianS1-3T`:

- `<sub>_atlas-<combined>_space-T1w_parcels.nii.gz`
- `<sub>_atlas-<combined>_space-dwi_parcels.nii.gz`
- `<sub>_atlas-<combined>_lut.txt`: combined FreeSurfer-style LUT.
- `<sub>_atlas-<combined>_nodes.tsv`: index, name, hemisphere, atlas source,
  and original label ID for every expected node.
- `<sub>_model-<model>_atlas-<combined>_connectome.csv`
- `<sub>_model-<model>_atlas-<combined>_assignments.csv`

Intermediates and ANTs transforms are retained in
`dwi/parcellation/<combined>/`. The mapping tables use the atlas definitions,
not each subject's surviving labels. Missing parcels are not renumbered.
MRtrix sizes the connectome from the largest label present in the DWI image;
if the highest node disappears, the matrix can be smaller than the node table.
The separate QC below reports this.

## Separate quality control commands

These commands are **not called by the job**. Run them after processing.
For a different cortical atlas, change `combined` accordingly.

```bash
session=/absolute/path/to/bids/sub-001/ses-1
subject=$(basename "$(dirname "$session")")
model=ss3t
combined=schaefer100-yeo7-tianS1-3T
dwi="$session/dwi"
work="$dwi/parcellation/$combined"
prefix="$dwi/${subject}_atlas-${combined}"
connectome_prefix="$dwi/${subject}_model-${model}_atlas-${combined}"

# Subject anatomy against the template used for registration.
# Use your SUBCORTICAL_TEMPLATE override here if you supplied one.
mrview "$FSLDIR/data/standard/MNI152_T1_2mm_brain.nii.gz" \
  -overlay.load "$work/T1w_to_subcortical_template_Warped.nii.gz"

# Inspect cortex and Tian separately on native anatomy before overlap removal.
mrview "$session/anat/${subject}_T1w.nii.gz" \
  -overlay.load "$work/cortex_space-T1w.nii.gz" \
  -overlay.load "$work/subcortex_space-T1w_labels.nii.gz"

# Final nodes against the actual diffusion reference and ACT interface.
mrview "$dwi/mean_b0_final.nii.gz" \
  -overlay.load "${prefix}_space-dwi_parcels.nii.gz" \
  -overlay.load "$dwi/${subject}_desc-coreg_gmwmi.mif"

# Optional: inspect endpoint locations using the existing display tractogram.
mrview "$dwi/mean_b0_final.nii.gz" \
  -overlay.load "${prefix}_space-dwi_parcels.nii.gz" \
  -tractography.load "$dwi/${subject}_model-${model}_tractogram-200k.tck"
```

Inspect thalamus, striatum, hippocampus and amygdala in both hemispheres, cortical
ribbon alignment, lesions, ventricular boundaries, and endpoint proximity.
Correct grids/interpolation do not establish anatomical registration quality.
Nearest-neighbour resampling can remove small parcels on the coarser DWI grid.

For integer labels, matching grids, node counts/volumes, overlap handling and
matrix shape, use a Python environment containing `nibabel` and `numpy`:

```bash
python - "$session" "$combined" "$model" <<'PY'
import csv
import sys
from pathlib import Path

import nibabel as nib
import numpy as np

session, combined, model = sys.argv[1:]
session = Path(session)
subject = session.parent.name
dwi = session / "dwi"
work = dwi / "parcellation" / combined
prefix = dwi / f"{subject}_atlas-{combined}"
with open(f"{prefix}_nodes.tsv") as f:
    nodes = list(csv.DictReader(f, delimiter="\t"))
expected = {int(row["index"]) for row in nodes}

for space, reference in [
    ("T1w", session / "anat" / f"{subject}_T1w.nii.gz"),
    ("dwi", dwi / "mean_b0_final.nii.gz"),
]:
    image = nib.load(f"{prefix}_space-{space}_parcels.nii.gz")
    ref = nib.load(reference)
    data = image.get_fdata()
    assert image.shape == ref.shape[:3], (space, "grid shape mismatch")
    assert np.allclose(image.affine, ref.affine, atol=1e-4), (space, "affine mismatch")
    assert np.isfinite(data).all() and np.equal(data, np.rint(data)).all(), space
    assert set(np.unique(data)) <= expected | {0}, (space, "unexpected IDs")
    counts = np.bincount(data.astype(np.int64).ravel(), minlength=max(expected) + 1)
    voxel_mm3 = abs(np.linalg.det(image.affine[:3, :3]))
    print(space, "missing nodes:", sorted(i for i in expected if counts[i] == 0))
    print("index\tname\tvoxels\tvolume_mm3")
    for row in nodes:
        i = int(row["index"])
        print(f"{i}\t{row['name']}\t{counts[i]}\t{counts[i] * voxel_mm3:.2f}")

cortex = nib.load(work / "cortex_space-T1w.nii.gz").get_fdata()
subcortex = nib.load(work / "subcortex_space-T1w_nodes.nii.gz").get_fdata()
merged = nib.load(f"{prefix}_space-T1w_parcels.nii.gz").get_fdata()
print("T1 overlap voxels assigned to cortex:", np.count_nonzero((cortex > 0) & (subcortex > 0)))
assert np.array_equal(merged, np.where(cortex > 0, cortex, subcortex))

matrix = np.loadtxt(dwi / f"{subject}_model-{model}_atlas-{combined}_connectome.csv", delimiter=",")
print("Matrix shape:", matrix.shape, "expected:", (len(expected), len(expected)))
assert matrix.shape == (len(expected), len(expected)), "missing highest node / wrong matrix size"
assert np.isfinite(matrix).all() and (matrix >= 0).all()
assert np.allclose(matrix, matrix.T) and np.allclose(np.diag(matrix), 0)
PY
```

To quantify streamline assignment separately without loading all assignments
into memory:

```bash
tckinfo "$dwi/${subject}_model-${model}_tractogram-10M.tck" -count
awk '!/^#/ && NF {n++} END {print "SIFT2 weight count:", n}' \
  "$dwi/${subject}_model-${model}_sift2-weights.txt"
awk -F '[,[:space:]]+' '
  !/^#/ && NF >= 2 {
      total++
      if ($1 > 0 && $2 > 0) both++
      if ($1 == 0 || $2 == 0) unassigned++
  }
  END {
      print "Streamlines:", total
      print "Both endpoints assigned:", both + 0
      print "At least one endpoint unassigned:", unassigned + 0
      if (total) printf "Both endpoints assigned: %.2f%%\n", 100 * both / total
  }
' "${connectome_prefix}_assignments.csv"
```

The assignments include self-connections even though the matrix diagonal is
zero. Review missing nodes and assignment coverage together with the overlays
before using a subject's combined connectome.
