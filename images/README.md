# Singularity in this pipeline

## What is Singularity?

Singularity runs software inside a **container**. A container is a packaged
environment containing the programs and libraries needed by a processing step.
Singularity containers are stored as `.sif` files.

Your data stay in the normal BIDS folders outside the container.

## Images used by the pipeline

- `diffusion_image.sif`: used for HD-BET, SS3T-CSD, and containerized FreeSurfer.
- `synb0-disco_v3.0.sif`: used for Synb0-DISCO.

Check that Singularity and the required image are available before processing:

```bash
module load singularity # Or install locally in computer
singularity --version
ls images/diffusion_image.sif images/synb0-disco_v3.0.sif
```

## The three things to understand

`exec` runs a command that you choose inside an image:

```bash
singularity exec IMAGE.sif COMMAND ARGUMENTS
```

`run` starts the default workflow stored in an image. The pipeline uses this
for Synb0-DISCO:

```bash
singularity run IMAGE.sif
```

`--bind` makes a host folder visible inside the container:

```text
--bind /host/folder:/container/folder
```

For example, `--bind /path/to/sub-001/anat:/anat` means that the subject's real
`anat/` folder is called `/anat` inside the container. Files written to
`/anat` appear in the real subject folder. `-B` is the short form of `--bind`.

## Running HD-BET yourself

Replace the paths and T1w filename:

```bash
PIPELINE_ROOT=/path/to/Tractography_pipeline
ANAT_DIR=/path/to/bids/sub-001/anat

singularity exec \
  --bind "$ANAT_DIR:/anat" \
  "$PIPELINE_ROOT/images/diffusion_image.sif" \
  hd-bet \
  -i /anat/sub-001_T1w.nii.gz \
  -o /anat/sub-001_desc-hdbet_T1w.nii.gz \
  --save_bet_mask -device cpu --disable_tta
```

The `/anat/...` paths are inside the container. The input and results are in
the host folder stored in `ANAT_DIR`.

## Running Synb0-DISCO yourself

The preprocessing script first prepares `INPUTS/` and `OUTPUTS/`. From the
subject's `dwi/` directory, run:

```bash
PIPELINE_ROOT=/path/to/Tractography_pipeline
module load FreeSurfer

singularity run -e \
  -B "$PWD/INPUTS:/INPUTS" \
  -B "$PWD/OUTPUTS:/OUTPUTS" \
  -B "$FREESURFER_HOME/license.txt:/extra/freesurfer/license.txt" \
  "$PIPELINE_ROOT/images/synb0-disco_v3.0.sif"
```

Synb0-DISCO reads `/INPUTS` and writes to `/OUTPUTS`. Loading FreeSurfer sets
`FREESURFER_HOME`, which locates the license file. The `-e` option gives the
container a clean environment.

Normally, you do not need to run these commands yourself. The pipeline scripts
load Singularity, create the bind mounts, and execute the container commands.
