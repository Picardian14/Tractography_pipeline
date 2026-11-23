"""Numerical checks for the surface-cortex / registered-subcortex route."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import nibabel as nib
import numpy as np


REPO = Path(__file__).resolve().parents[1]
SCRIPTS = REPO / "scripts/6_parcellation"
spec = importlib.util.spec_from_file_location("combined_qc", SCRIPTS / "qc_cortico_subcortical.py")
qc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qc)


@unittest.skipUnless(all(shutil.which(command) for command in ("mrconvert", "mrtransform", "mrcalc", "labelconvert")),
                     "MRtrix must be installed or loaded")
class CorticoSubcorticalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.session = self.root / "sub-001/ses-1"
        self.dwi = self.session / "dwi"
        self.anat = self.session / "anat"
        self.fs = self.root / "freesurfer"
        self.subject = self.fs / "sub-001_ses-1"
        for path in (self.dwi, self.anat, self.subject / "mri", self.subject / "label", self.fs / "fsaverage"):
            path.mkdir(parents=True, exist_ok=True)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("BASH_FUNC_")}
        self.env.update(PIPELINE_ROOT=str(REPO), FREESURFER_SUBJECTS_DIR=str(self.fs),
                        ATLAS_ROOT=str(self.root / "atlases"), ATLAS_LABEL_NAME="arbitrary-cortex",
                        SUBCORTICAL_LABEL_NAME="test-subcortex", NTHREADS="1", MRTRIX_QUIET="1")
        self.affine = np.eye(4)
        cortex = np.zeros((5, 5, 5), dtype=np.int32)
        cortex[1, 1, 1] = 1001
        cortex[3, 3, 3] = 2001
        cortex[0, 0, 0] = 17  # Inherited aseg hippocampus must not become cortex.
        self.cortex_fixture = self.root / "cortex.mgz"
        nib.save(nib.MGHImage(cortex, self.affine), self.cortex_fixture)
        for filename in ("brain.mgz", "ribbon.mgz"):
            shutil.copyfile(self.cortex_fixture, self.subject / "mri" / filename)
        nib.save(nib.Nifti1Image(np.ones(cortex.shape, dtype=np.float32), self.affine), self.anat / "sub-001_T1w.nii.gz")
        self.subcortex = np.zeros(cortex.shape, dtype=np.uint32)
        self.subcortex[1, 1, 1] = 7  # Deliberate overlap: cortex must win here.
        self.subcortex[3, 2, 1] = 7
        self.subcortex[4, 4, 4] = 19
        self.subcortex_fixture = self.root / "subcortex.nii.gz"
        nib.save(nib.Nifti1Image(self.subcortex, self.affine), self.subcortex_fixture)
        self.T1_to_DWI = np.eye(4)
        self.T1_to_DWI[:3, 3] = [2, -3, 4]
        np.savetxt(self.dwi / "rigid_T1toDWI.txt", self.T1_to_DWI)
        for model in ("msmt", "ss3t"):
            (self.dwi / f"sub-001_model-{model}_tractogram-10M.tck").write_text("stub tracks")
            (self.dwi / f"sub-001_model-{model}_sift2-weights.txt").write_text("1\n")
        atlas = self.root / "atlases/arbitrary-cortex"
        atlas.mkdir(parents=True)
        (atlas / "LUT_arbitrary-cortex.txt").write_text("17 HIP 1 2 3 0\n1001 LeftName 1 2 3 0\n2001 RightName 4 5 6 0\n")
        # Preserve the requested output order even when it differs from source IDs.
        (atlas / "LUT_arbitrary-cortex_OUTPUT.txt").write_text("1 RightName 4 5 6 0\n2 LeftName 1 2 3 0\n")
        for hemi in ("lh", "rh"):
            (atlas / f"{hemi}.arbitrary-cortex.annot").write_text("stub annotation")
        sub_lut = self.root / "subcortex_lut.txt"
        sub_lut.write_text("7 RegionA-rh\n19 RegionB-lh\n")
        self.env["SUBCORTICAL_LUT"] = str(sub_lut)
        self.install_stubs()

    def install_stubs(self):
        stub_dir = self.root / "bin"
        stub_dir.mkdir()
        stub = """#!/usr/bin/env python3
import json, os, shutil, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['TEST_LOG'], 'a') as stream:
    stream.write(json.dumps([name] + args) + '\\n')
if name == 'mri_aparc2aseg':
    shutil.copyfile(os.environ['TEST_CORTEX'], args[args.index('--o') + 1])
elif name == 'antsRegistrationSyN.sh':
    prefix = args[args.index('-o') + 1]
    for suffix in ('0GenericAffine.mat', '1Warp.nii.gz'):
        Path(prefix + suffix).write_text('stub transform')
elif name == 'antsApplyTransforms':
    shutil.copyfile(os.environ['TEST_SUBCORTEX'], args[args.index('-o') + 1])
elif name == 'tck2connectome':
    Path(args[2]).write_text('0,1,1,1\\n1,0,1,1\\n1,1,0,1\\n1,1,1,0\\n')
    Path(args[args.index('-out_assignments') + 1]).write_text('1 3\\n')
"""
        for name in ("ml", "mri_surf2surf", "mri_aparc2aseg", "antsRegistrationSyN.sh", "antsApplyTransforms", "tck2connectome"):
            path = stub_dir / name
            path.write_text(stub)
            path.chmod(0o755)
        fs_home = self.root / "fs_home"
        fs_home.mkdir()
        (fs_home / "SetUpFreeSurfer.sh").write_text(":\n")
        self.env.update(PATH=str(stub_dir) + os.pathsep + self.env["PATH"], FREESURFER_HOME=str(fs_home),
                        TEST_LOG=str(self.root / "commands.jsonl"), TEST_CORTEX=str(self.cortex_fixture),
                        TEST_SUBCORTEX=str(self.subcortex_fixture))

    def run_job(self):
        result = subprocess.run(["bash", str(SCRIPTS / "parcellate_cortico_subcortical_job.sh"), str(self.session)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_supplied_native_map_merges_without_registration(self):
        self.env["SUBCORTICAL_NATIVE"] = str(self.subcortex_fixture)
        timing_log = self.root / "workflow.timing.log"
        self.env.update(WORKFLOW_START_EPOCH="1", WORKFLOW_TIMING_LOG=str(timing_log))
        self.run_job()
        self.assertIn("parcellation completed successfully for sub-001_ses-1", timing_log.read_text())
        prefix = self.dwi / "sub-001_atlas-arbitrary-cortex-test-subcortex"
        native = nib.load(f"{prefix}_space-T1w_parcels.nii.gz")
        labels = np.asarray(native.dataobj)
        self.assertEqual(labels[1, 1, 1], 2)
        self.assertEqual(labels[3, 3, 3], 1)
        self.assertEqual(labels[3, 2, 1], 3)
        self.assertEqual(labels[4, 4, 4], 4)
        self.assertEqual(labels[0, 0, 0], 0)
        diffusion = nib.load(f"{prefix}_space-dwi_parcels.nii.gz")
        np.testing.assert_array_equal(diffusion.dataobj, labels)
        np.testing.assert_allclose(diffusion.affine, np.linalg.inv(self.T1_to_DWI) @ native.affine)
        self.assertEqual(diffusion.get_data_dtype(), np.dtype('uint32'))
        qc.check_parcellation(self.session, "arbitrary-cortex-test-subcortex")
        calls = [json.loads(line) for line in Path(self.env["TEST_LOG"]).read_text().splitlines()]
        self.assertFalse(any(call[0].startswith("ants") for call in calls))
        aparc = next(call for call in calls if call[0] == "mri_aparc2aseg")
        self.assertIn("--ribbon", aparc)

        # QC must identify unknown source labels even if labelconvert discarded them.
        source = self.dwi / "parcellation/arbitrary-cortex-test-subcortex/subcortex_space-T1w_labels.nii.gz"
        image = nib.load(source)
        bad_labels = np.array(image.dataobj)
        bad_labels[0, 0, 0] = 99
        nib.save(nib.Nifti1Image(bad_labels, image.affine), source)
        with self.assertRaisesRegex(ValueError, "missing from the LUT"):
            qc.check_parcellation(self.session, "arbitrary-cortex-test-subcortex")

    def test_downloaded_layout_registers_once_and_reuses_native_map(self):
        atlas = self.root / "atlases/arbitrary-cortex"
        (atlas / "lut").mkdir()
        (atlas / "surface/fsaverage").mkdir(parents=True)
        for path in atlas.glob("*.txt"):
            path.rename(atlas / "lut" / path.name)
        for hemi in ("lh", "rh"):
            (atlas / f"{hemi}.arbitrary-cortex.annot").rename(atlas / "surface/fsaverage" / f"{hemi}.downloaded-name.annot")
        self.env.update(SUBCORTICAL_ATLAS=str(self.subcortex_fixture),
                        SUBCORTICAL_TEMPLATE=str(self.anat / "sub-001_T1w.nii.gz"), MODEL="ss3t")
        self.run_job()
        self.run_job()
        qc.check_parcellation(self.session, "arbitrary-cortex-test-subcortex", "ss3t")
        calls = [json.loads(line) for line in Path(self.env["TEST_LOG"]).read_text().splitlines()]
        registrations = [call for call in calls if call[0] == "antsRegistrationSyN.sh"]
        self.assertEqual(len(registrations), 1)
        registration = registrations[0]
        self.assertTrue(registration[registration.index('-f') + 1].endswith('T1w_brain.nii.gz'))
        self.assertEqual(registration[registration.index('-m') + 1], self.env['SUBCORTICAL_TEMPLATE'])
        apply = next(call for call in calls if call[0] == "antsApplyTransforms")
        transforms = [apply[i + 1] for i, arg in enumerate(apply) if arg == '-t']
        self.assertTrue(transforms[0].endswith('1Warp.nii.gz'))
        self.assertTrue(transforms[1].endswith('0GenericAffine.mat'))
        self.assertEqual(apply[apply.index('-n') + 1], 'NearestNeighbor')

    def test_unmatched_cortical_lookup_fails_before_processing(self):
        self.env["SUBCORTICAL_NATIVE"] = str(self.subcortex_fixture)
        table = self.root / "atlases/arbitrary-cortex/LUT_arbitrary-cortex_OUTPUT.txt"
        table.write_text("1 MissingName 1 2 3 0\n")
        result = subprocess.run(["bash", str(SCRIPTS / "parcellate_cortico_subcortical_job.sh"), str(self.session)],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unmatched cortical LUT name", result.stderr)


if __name__ == "__main__":
    unittest.main()
