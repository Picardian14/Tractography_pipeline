"""Small numerical checks for HCP preparation and shared stage compatibility."""

import hashlib
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
PREPARE = REPO / "scripts/2_preprocessing/prepare_hcp_for_processing.sh"


def make_hcp_subject(root, subject="sub-100307"):
    t1_dir = root / "sourcedata/hcp" / subject / "T1w"
    (t1_dir / "Diffusion").mkdir(parents=True)
    t1_affine = np.diag([-0.7, 0.7, 0.7, 1])
    dwi_affine = np.diag([-1.25, 1.25, 1.25, 1])
    t1_mask = np.zeros((8, 8, 8), dtype=np.uint8)
    t1_mask[1:-1, 1:-1, 1:-1] = 1
    dwi_mask = np.zeros((5, 5, 5), dtype=np.uint8)
    dwi_mask[1:-1, 1:-1, 1:-1] = 1
    for filename, data, affine in [
        ("T1w_acpc_dc_restore.nii.gz", t1_mask * 100, t1_affine),
        ("T1w_acpc_dc_restore_brain.nii.gz", t1_mask * 100, t1_affine),
        ("brainmask_fs.nii.gz", t1_mask, t1_affine),
        ("T1w_acpc_dc_restore_1.25.nii.gz", dwi_mask * 100, dwi_affine),
        ("Diffusion/nodif_brain_mask.nii.gz", dwi_mask, dwi_affine),
        ("Diffusion/data.nii.gz", np.broadcast_to(np.array([10, 20, 30, 40], dtype=np.float32), (5, 5, 5, 4)), dwi_affine),
    ]:
        nib.save(nib.Nifti1Image(data, affine), t1_dir / filename)
    np.savetxt(t1_dir / "Diffusion/bvals", [[0, 0, 1000, 2000]])
    np.savetxt(t1_dir / "Diffusion/bvecs", [[0, 0, 1, 0], [0, 0, 0, 1], [0, 0, 0, 0]])
    return t1_dir


@unittest.skipUnless(all(shutil.which(cmd) for cmd in ("mrconvert", "dwiextract", "mrmath", "mrtransform", "5tt2gmwmi")),
                     "MRtrix must be installed or loaded")
class HCPPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.output = self.root / "prepared"
        self.t1_dir = make_hcp_subject(self.source)
        # Exported module functions would override the test executables and
        # load real cluster software instead of the controlled external stubs.
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("BASH_FUNC_")}
        self.env["MRTRIX_QUIET"] = "1"
        self.env["PYTHONDONTWRITEBYTECODE"] = "1"
        self.session = self.output / "sub-100307/ses-1"

    def prepare(self):
        result = subprocess.run(["bash", str(PREPARE), str(self.source), str(self.output), "--subject", "100307"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def install_stubs(self):
        """Replace expensive external tools; leave MRtrix geometry operations real."""
        stub_dir = self.root / "bin"
        stub_dir.mkdir(exist_ok=True)
        stub = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
import nibabel as nib
import numpy as np
name = Path(sys.argv[0]).name
args = sys.argv[1:]
log = Path(os.environ['TEST_COMMAND_LOG'])
with log.open('a') as stream:
    stream.write(json.dumps([name] + args) + '\\n')
if name == '5ttgen':
    image = nib.load(os.environ['TEST_T1'])
    mask = np.asarray(image.dataobj) > 0
    tissues = np.zeros(image.shape + (5,), dtype=np.float32)
    tissues[..., 0] = mask * 0.4
    tissues[..., 2] = mask * 0.6
    temporary = Path(args[2]).with_suffix('.nii.gz')
    nib.save(nib.Nifti1Image(tissues, image.affine), temporary)
    import subprocess
    subprocess.run(['mrconvert', str(temporary), args[2], '-force', '-quiet'], check=True)
elif name == 'labelconvert':
    import shutil
    shutil.copyfile(args[0], args[3])
elif name == 'dwi2response':
    for filename in args[2:5]:
        Path(filename).write_text('1 0 0\\n')
elif name == 'tck2connectome':
    Path(args[args.index('-out_assignment') + 1]).write_text('1,2\\n')
    Path(args[args.index('-out_assignment') - 1]).write_text('0,1\\n1,0\\n')
elif name == 'sbatch':
    print(1000 + sum(1 for line in log.read_text().splitlines() if json.loads(line)[0] == 'sbatch'))
"""
        for name in ("module", "ml", "5ttgen", "dwi2response", "mri_surf2surf", "mri_aparc2aseg", "labelconvert", "tck2connectome", "sbatch"):
            path = stub_dir / name
            path.write_text(stub)
            path.chmod(0o755)
        self.env["PATH"] = str(stub_dir) + os.pathsep + self.env["PATH"]
        self.env["TEST_COMMAND_LOG"] = str(self.root / "commands.jsonl")
        self.env["TEST_T1"] = str(self.session / "anat/sub-100307_T1w.nii.gz")
        fs_home = self.root / "fs_home"
        fs_home.mkdir(exist_ok=True)
        (fs_home / "subjects/fsaverage").mkdir(parents=True)
        (fs_home / "SetUpFreeSurfer.sh").write_text(":\n")
        self.env["FREESURFER_HOME"] = str(fs_home)
        self.env["FREESURFER_SUBJECTS_DIR"] = str(self.root / "freesurfer")
        self.env["PIPELINE_ROOT"] = str(REPO)
        self.env["OUTPUT_DIR"] = str(self.root / "logs")

    def test_one_subject_preserves_inputs_gradients_and_reruns(self):
        make_hcp_subject(self.source, "sub-100408")
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in self.source.rglob("*") if path.is_file()}
        self.prepare()
        self.assertEqual([p.name for p in self.output.glob("sub-*")], ["sub-100307"])
        dwi_dir = self.session / "dwi"
        copied = dwi_dir / "sub-100307_desc-preproc_dwi.nii.gz"
        self.assertFalse(copied.samefile(self.t1_dir / "Diffusion/data.nii.gz"))
        np.testing.assert_allclose(nib.load(dwi_dir / "mean_b0_final.nii.gz").get_fdata(), 15)
        np.testing.assert_array_equal(np.loadtxt(dwi_dir / "rigid_T1toDWI.txt"), np.eye(4))
        exported_bvecs, exported_bvals = self.root / "bvecs", self.root / "bvals"
        subprocess.run(["mrinfo", str(dwi_dir / "sub-100307_desc-preproc_dwi.mif"),
                        "-export_grad_fsl", str(exported_bvecs), str(exported_bvals), "-quiet"], check=True, env=self.env)
        np.testing.assert_allclose(np.loadtxt(exported_bvals), np.loadtxt(self.t1_dir / "Diffusion/bvals"))
        np.testing.assert_allclose(np.loadtxt(exported_bvecs), np.loadtxt(self.t1_dir / "Diffusion/bvecs"))
        mif = dwi_dir / "sub-100307_desc-preproc_dwi.mif"
        timestamp = mif.stat().st_mtime_ns
        self.prepare()
        self.assertEqual(mif.stat().st_mtime_ns, timestamp)
        self.assertEqual(before, {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in before})
        mask_nii = self.root / "converted_mask.nii.gz"
        subprocess.run(["mrconvert", str(dwi_dir / "sub-100307_desc-resampled_bet.mif"), str(mask_nii), "-quiet"],
                       check=True, env=self.env)
        np.testing.assert_array_equal(nib.load(mask_nii).get_fdata(), nib.load(self.t1_dir / "Diffusion/nodif_brain_mask.nii.gz").get_fdata())

    def test_bad_geometry_and_gradient_count_are_rejected(self):
        mask = self.t1_dir / "Diffusion/nodif_brain_mask.nii.gz"
        image = nib.load(mask)
        wrong_affine = image.affine.copy()
        wrong_affine[0, 3] += 5
        nib.save(nib.Nifti1Image(image.get_fdata(), wrong_affine), mask)
        result = subprocess.run(["bash", str(PREPARE), str(self.source), str(self.output), "--subject", "100307"],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("grids disagree", result.stderr)
        self.assertFalse(self.output.exists())
        nib.save(nib.Nifti1Image(image.get_fdata(), image.affine), mask)
        np.savetxt(self.t1_dir / "Diffusion/bvals", [[0, 1000]])
        result = subprocess.run(["bash", str(PREPARE), str(self.source), str(self.output), "--subject", "100307"],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("gradient counts", result.stderr)

    def test_tissues_reuse_hcp_mask_and_doc_keeps_unmasked_branch(self):
        self.prepare()
        self.install_stubs()
        dwi_dir = self.session / "dwi"
        result = subprocess.run(["bash", str(REPO / "scripts/4_segment5tt/tissue_job.sh"), str(self.session)],
                                cwd=dwi_dir, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in Path(self.env["TEST_COMMAND_LOG"]).read_text().splitlines()]
        self.assertIn("-mask", next(call for call in calls if call[0] == "5ttgen"))
        tissue_nii = dwi_dir / "sub-100307_desc-coreg_5tt.nii.gz"
        np.testing.assert_allclose(nib.load(tissue_nii).affine, nib.load(self.env["TEST_T1"]).affine, atol=1e-5)
        self.assertTrue((dwi_dir / "sub-100307_desc-coreg_gmwmi.mif").is_file())

        # Removing only the optional supplied mask represents the DoC branch.
        (self.session / "anat/sub-100307_space-T1w_desc-brain_mask.nii.gz").unlink()
        (dwi_dir / "sub-100307_desc-coreg_5tt.mif").unlink()
        (dwi_dir / "sub-100307_desc-coreg_gmwmi.mif").unlink()
        M = np.eye(4)
        M[:3, 3] = [2, -3, 4]
        np.savetxt(dwi_dir / "rigid_T1toDWI.txt", M)
        np.savetxt(dwi_dir / "rigid_T1toDWI.mat", M)
        result = subprocess.run(["bash", str(REPO / "scripts/4_segment5tt/tissue_job.sh"), str(self.session)],
                                cwd=dwi_dir, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in Path(self.env["TEST_COMMAND_LOG"]).read_text().splitlines()]
        self.assertNotIn("-mask", [call for call in calls if call[0] == "5ttgen"][-1])
        np.testing.assert_allclose(nib.load(tissue_nii).affine, np.linalg.inv(M) @ nib.load(self.env["TEST_T1"]).affine, atol=1e-5)

    def test_response_estimation_restores_the_supplied_final_mask(self):
        self.prepare()
        self.install_stubs()
        dwi_dir = self.session / "dwi"
        mask_mif = dwi_dir / "sub-100307_desc-resampled_bet.mif"
        mask_mif.unlink()
        mif = dwi_dir / "sub-100307_desc-preproc_dwi.mif"
        timestamp = mif.stat().st_mtime_ns
        result = subprocess.run(["bash", str(REPO / "scripts/3_deconvolution/dwi2response.sh"), str(self.session)],
                                cwd=dwi_dir, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(mif.stat().st_mtime_ns, timestamp)
        mask_nii = self.root / "restored_mask.nii.gz"
        subprocess.run(["mrconvert", str(mask_mif), str(mask_nii), "-quiet"], check=True,
                       env=self.env, capture_output=True)
        np.testing.assert_array_equal(nib.load(mask_nii).get_fdata(),
                                      nib.load(self.t1_dir / "Diffusion/nodif_brain_mask.nii.gz").get_fdata())

    def test_both_parcellation_routes_preserve_labels_in_diffusion_coordinates(self):
        self.prepare()
        self.install_stubs()
        dwi_dir = self.session / "dwi"
        fs_mri = Path(self.env["FREESURFER_SUBJECTS_DIR"]) / "sub-100307_ses-1/mri"
        fs_mri.mkdir(parents=True)
        labels = np.zeros((5, 5, 5), dtype=np.int32)
        labels[1:3] = 1
        labels[3:4] = 2
        affine = np.diag([-1., 1., 1., 1.])
        nib.save(nib.MGHImage(labels, affine), fs_mri / "schaefer100-yeo7.mgz")
        for model, translation in (("msmt", [0, 0, 0]), ("ss3t", [2, -3, 4])):
            with self.subTest(model=model):
                M = np.eye(4)
                M[:3, 3] = translation
                np.savetxt(dwi_dir / "rigid_T1toDWI.txt", M)
                (dwi_dir / f"sub-100307_model-{model}_sift2-weights.txt").write_text("1\n")
                (dwi_dir / f"sub-100307_model-{model}_tractogram-10M.tck").touch()
                result = subprocess.run(["bash", str(REPO / f"scripts/6_parcellation/parcellate_{model}_job.sh"), str(self.session)],
                                        cwd=dwi_dir, env=self.env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                parcels = nib.load(dwi_dir / "sub-100307_atlas-schaefer100-yeo7_space-dwi_parcels.nii.gz")
                np.testing.assert_array_equal(parcels.get_fdata(), labels)
                np.testing.assert_allclose(parcels.affine, np.linalg.inv(M) @ affine, atol=1e-5)
        calls = [json.loads(line) for line in Path(self.env["TEST_COMMAND_LOG"]).read_text().splitlines()]
        connectomes = [call for call in calls if call[0] == "tck2connectome"]
        self.assertEqual(len(connectomes), 2)
        self.assertTrue(all(any("space-dwi_parcels" in arg for arg in call) for call in connectomes))
        self.assertTrue((Path(self.env["FREESURFER_SUBJECTS_DIR"]) / "fsaverage").samefile(
            Path(self.env["FREESURFER_HOME"]) / "subjects/fsaverage"))

    def test_msmt_launcher_submits_only_the_prepared_subject(self):
        self.prepare()
        self.install_stubs()
        result = subprocess.run(["bash", str(REPO / "scripts/3_to_6_msmt.sh"), str(self.output)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in Path(self.env["TEST_COMMAND_LOG"]).read_text().splitlines()]
        self.assertEqual(len(calls), 7)
        self.assertTrue(all(call[0] == "sbatch" for call in calls))
        self.assertFalse(any("sub-100408" in str(call) for call in calls))
        mean = next(call for call in calls if any(arg.endswith("/2_responsemean.sh") for arg in call))
        self.assertIn("--dependency=afterok:1001", mean)
        tracks = next(call for call in calls if any(arg.endswith("/tckgen_msmt_job.sh") for arg in call))
        self.assertIn("--dependency=afterok:1005:1002", tracks)


if __name__ == "__main__":
    unittest.main()
