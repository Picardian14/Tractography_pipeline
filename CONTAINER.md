# Diffusion container

[`diffusion.def`](diffusion.def) installs the command-line software used by the
pipeline scripts:

- MRtrix3Tissue `3Tissue_v5.2.9` at commit
  `f8ba0e3fa17cb3b6bb51bcc4939cde83243b8f4c`, including
  `ss3t_csd_beta1`
- FSL tools used directly or through MRtrix (`eddy`, `topup`, `flirt`, BET,
  FAST/FIRST, `fslroi`) and the MNI standard data
- ANTs, including N4 bias correction
- HD-BET at commit `678e44d546a84de0f2a7fc245f176b82b7d912fd`,
  with its model weights downloaded during the build
- dcm2bids, dcm2niix, and FreeSurfer 6.0.0 (matching the explicit module
  version in the parcellation and reconstruction scripts)

The MRtrix and HD-BET commits match the Git checkouts inspected on the
development machine. The command currently installed as `hd-bet` on that
machine is an older HD-BET 1.1 package under Python 3.7, despite the checkout
being v2.0.1-era. The definition uses the inspected Git checkout because its
CLI still supports the pipeline's `-device cpu --disable_tta` options and it is
maintained on a supported Python version.

The Conda environment is created with Miniforge, `--override-channels`, the
required temporary `-k` SSL workaround, the FSL public channel, and
conda-forge. It does not use Anaconda's `defaults`, `main`, `pytorch`, or
`nvidia` channels. In accordance with the institute's Miniforge migration
instructions, CPU PyTorch is installed with pip from
`https://download.pytorch.org/whl/cpu`.

MRtrix is built separately from Conda using the documented system
dependencies, repository clone, tagged checkout, `./configure -nogui`, and
`./build` sequence. It explicitly uses Ubuntu 22.04's `/usr/bin/gcc-11` and
`/usr/bin/g++-11`. The generic `gcc`, `g++`, `cc`, and `c++` commands are also
linked to version 11 for any subsequent source build. No Conda compiler or
Conda activation is used for MRtrix.

MRtrix3Tissue `3Tissue_v5.2.9` is configured specifically against Eigen 3.3.9
under `/opt/eigen-3.3.9`, matching the known-working local configuration.
Ubuntu 22.04's Eigen 3.4 remains available to other software. Eigen 3.4 cannot
be used for this old fork because both Eigen 3.4 and the fork declare
`Eigen::Vector3` with incompatible meanings. The definition passes
`EIGEN_CFLAGS="-isystem /opt/eigen-3.3.9"` to `./configure` and verifies the
generated MRtrix `config` before compilation starts.

The host compiler remains isolated from the image, but the image has its own
GCC/G++ 11. NumPy 2.2.6 and scikit-image 0.25.2 are installed from prebuilt
Python 3.11 manylinux wheels with `--only-binary=:all:` to keep the Python
environment deterministic.

## Build

The image uses Ubuntu 22.04 as its base. FreeSurfer 6.0.0 is downloaded from
the official archive and extracted under `/usr/local/freesurfer`; the old
FreeSurfer container is not used as the base. The image is large because
FreeSurfer alone is several gigabytes. Build it in a location with ample
temporary and cache space:

```bash
export BUILD_TMPDIR=/path/with/at-least-40GB-free
export BUILD_CACHEDIR=/path/with/at-least-20GB-free
bash build_diffusion_image.sh
```

The wrapper detects SingularityCE or Apptainer and writes the complete
stdout/stderr stream to a timestamped file under `build-logs/`. It enables
`--no-cleanup` when available and also sets the corresponding
`SINGULARITY_NOCLEANUP` or `APPTAINER_NOCLEANUP` variable, and returns the
original non-zero build status. When run as a non-root user it
adds `--fakeroot`; this requires fakeroot/subordinate-ID support to be enabled
by the cluster administrator. After a failure,
search the end of the log for the retained bundle location:

```bash
tail -n 100 build-logs/diffusion-build-*.log
grep -Ei 'bundle|build-temp|tmp' build-logs/diffusion-build-*.log
```

Singularity builds the definition's `%post` as one transaction. A retained
failed bundle allows inspection of the filesystem at the point of failure, but
it is not a supported automatic restart checkpoint. Re-running the wrapper
starts the definition again, while downloads already held in the runtime cache
can be reused. True resumable installation requires splitting the definition
into separately built intermediate images (for example, Ubuntu/FreeSurfer,
then FSL, then MRtrix/HD-BET) and using each completed SIF as the next build's
base.

The definition targets Linux x86-64. HD-BET is configured for CPU inference,
which matches the current pipeline invocation and avoids coupling the image to
a host CUDA version.

## Test and run

The definition has a `%test` section, which runs automatically at the end of a
normal build. It can be rerun with:

```bash
apptainer test diffusion.sif
```

FreeSurfer is free but requires a personal `license.txt`. Do not bake that file
into the image or commit it to Git:

```bash
apptainer exec \
  --bind /secure/path/license.txt:/usr/local/freesurfer/license.txt:ro \
  --bind /data:/data \
  diffusion.sif \
  recon-all -all -s SUBJECT -i /data/T1_raw.nii.gz
```

For an interactive shell:

```bash
apptainer shell --cleanenv \
  --bind /secure/path/license.txt:/usr/local/freesurfer/license.txt:ro \
  --bind /data:/data \
  diffusion.sif
```

The existing preprocessing script launches synb0-disco through a separate SIF.
Nested Apptainer/Singularity is fragile and commonly prohibited on clusters, so
this image deliberately does not install a container runtime. Keep the
synb0-disco step on the host or refactor it into a separate submitted step.

The Slurm scripts also contain `module load`/`ml` statements. Those are
site-specific and should not be executed inside this image; invoke the worker
scripts through `apptainer exec` after loading only Apptainer/Singularity on the
host.
