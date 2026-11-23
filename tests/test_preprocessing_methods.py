"""Check acquisition rows and method switching with small, real MRtrix images."""

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
PREPROCESS = REPO / "scripts/2_preprocessing/preprocess_single_subject.sh"
ACQPARAMS = REPO / "scripts/2_preprocessing/create_acqparams.py"
LAUNCHER = REPO / "scripts/2_preprocessing/1_submits_all_subs_preproc.sh"


class AcquisitionParametersTests(unittest.TestCase):
    def test_synthetic_and_acquired_reference_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dwi, reverse, output = root / "dwi.json", root / "reverse.json", root / "acqparams.txt"
            for phase in ("j", "j-"):
                direction = 1 if phase == "j" else -1
                dwi.write_text(json.dumps({"PhaseEncodingDirection": phase, "TotalReadoutTime": 0.06}))
                result = subprocess.run(["python3", str(ACQPARAMS), str(dwi), str(output)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                np.testing.assert_allclose(np.loadtxt(output), [[0, direction, 0, 0.06], [0, direction, 0, 0]])
                reverse.write_text(json.dumps({"PhaseEncodingDirection": "j-" if phase == "j" else "j",
                                               "TotalReadoutTime": 0.07}))
                result = subprocess.run(["python3", str(ACQPARAMS), str(dwi), str(output), str(reverse)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                np.testing.assert_allclose(np.loadtxt(output), [[0, direction, 0, 0.06], [0, -direction, 0, 0.07]])

    def test_invalid_reverse_metadata_does_not_overwrite_parameters(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dwi, reverse, output = root / "dwi.json", root / "reverse.json", root / "acqparams.txt"
            dwi.write_text(json.dumps({"PhaseEncodingDirection": "j-", "TotalReadoutTime": 0.06}))
            for metadata in [
                {"PhaseEncodingDirection": "j-", "TotalReadoutTime": 0.07},
                {"PhaseEncodingDirection": "j"},
                {"PhaseEncodingDirection": "j", "TotalReadoutTime": 0},
                {"PhaseEncodingDirection": "j", "TotalReadoutTime": -1},
                {"PhaseEncodingDirection": "j", "TotalReadoutTime": "nan"},
            ]:
                reverse.write_text(json.dumps(metadata))
                output.write_text("previous valid parameters\n")
                result = subprocess.run(["python3", str(ACQPARAMS), str(dwi), str(output), str(reverse)],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output.read_text(), "previous valid parameters\n")


@unittest.skipUnless(all(shutil.which(cmd) for cmd in
                         ("mrconvert", "dwiextract", "mrmath", "mrtransform", "mrcalc", "dwi2tensor", "tensor2metric", "flock")),
                     "MRtrix and flock must be available")
class PreprocessingMethodTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.session = self.root / "bids/sub-001/ses-1"
        self.dwi = self.session / "dwi"
        anat, fmap = self.session / "anat", self.session / "fmap"
        for directory in (self.dwi, anat, fmap):
            directory.mkdir(parents=True)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("BASH_FUNC_")}
        self.env.update(MRTRIX_QUIET="1", PYTHONDONTWRITEBYTECODE="1", PIPELINE_ROOT=str(REPO))
        affine = np.diag([-2., 2., 2., 1.])
        data = np.broadcast_to(np.array([100, 70, 60, 50, 65, 55, 60], dtype=np.float32), (8, 8, 8, 7))
        self.raw = self.dwi / "sub-001_dwi.nii.gz"
        nib.save(nib.Nifti1Image(data, affine), self.raw)
        self.metadata = self.dwi / "sub-001_dwi.json"
        self.metadata.write_text(json.dumps({"PhaseEncodingDirection": "j-", "TotalReadoutTime": 0.06}))
        np.savetxt(self.dwi / "sub-001_dwi.bval", [[0, 1000, 1000, 1000, 1000, 1000, 1000]])
        bvecs = np.array([[0, 1, 0, 0, 1, 1, 0], [0, 0, 1, 0, 1, 0, 1], [0, 0, 0, 1, 0, 1, 1]], dtype=float)
        bvecs[:, 4:] /= np.sqrt(2)
        np.savetxt(self.dwi / "sub-001_dwi.bvec", bvecs)
        mask = np.zeros((8, 8, 8), dtype=np.uint8)
        mask[1:-1, 1:-1, 1:-1] = 1
        for name, values in [("sub-001_T1w.nii.gz", mask * 100),
                             ("sub-001_desc-hdbet_T1w.nii.gz", mask * 100),
                             ("sub-001_desc-hdbet_T1w_bet.nii.gz", mask)]:
            nib.save(nib.Nifti1Image(values, affine), anat / name)
        self.reverse = self.dwi / "sub-001_acq-inverted_b0.nii.gz"
        nib.save(nib.Nifti1Image(np.ones((8, 8, 8, 2), dtype=np.float32) * 90, affine), self.reverse)
        self.reverse_json = self.dwi / "sub-001_acq-inverted_b0.json"
        self.reverse_json.write_text(json.dumps({"PhaseEncodingDirection": "j", "TotalReadoutTime": 0.07}))
        self.env["MNI_TEMPLATE"] = str(anat / "sub-001_T1w.nii.gz")
        self.env["SYNB0_SIF"] = str(self.root / "synb0.sif")
        Path(self.env["SYNB0_SIF"]).touch()
        self.env["FREESURFER_HOME"] = str(self.root)
        self.env["TEST_COMMAND_LOG"] = str(self.root / "commands.jsonl")
        subprocess.run(["mrconvert", str(self.raw), str(self.dwi / "Diff.mif"), "-fslgrad",
                        str(self.dwi / "sub-001_dwi.bvec"), str(self.dwi / "sub-001_dwi.bval")],
                       env=self.env, capture_output=True, check=True)
        # Denoising is shared and unchanged; test the method-dependent path.
        for name in ("Diff_den.mif", "Diff_den_gibbs.mif"):
            shutil.copyfile(self.dwi / "Diff.mif", self.dwi / name)
        self.install_external_stubs()

    def install_external_stubs(self):
        stub_dir = self.root / "bin"
        stub_dir.mkdir()
        stub = r'''#!/usr/bin/env python3
import json, os, shutil, subprocess, sys
from pathlib import Path
import nibabel as nib
import numpy as np

name, args = Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ['TEST_COMMAND_LOG'], 'a') as stream:
    stream.write(json.dumps([name, str(Path.cwd())] + args) + '\n')

def value(flag):
    return args[args.index(flag) + 1]

def option(flag):
    return next(arg.split('=', 1)[1] for arg in args if arg.startswith(flag + '='))

def save(data, reference, destination):
    image = nib.load(reference)
    nib.save(nib.Nifti1Image(np.asarray(data, dtype=np.float32), image.affine), destination)

if name == 'module':
    pass
elif name == 'sbatch':
    print('12345')
elif name in ('singularity', 'topup'):
    if os.environ.get('TEST_FAIL_TOPUP'):
        sys.exit(1)
    if name == 'topup':
        pair = nib.load(option('--imain'))
        reference = nib.load('INPUTS/b0.nii.gz')
        assert pair.shape == reference.shape[:3] + (2,), pair.shape
        np.testing.assert_allclose(pair.affine, reference.affine, atol=1e-5)
        if any(size % 2 for size in reference.shape[:3]):
            assert option('--subsamp') == '1,1,1,1,1,1,1,1,1'
        np.testing.assert_allclose(np.loadtxt(option('--datain')), [[0, -1, 0, .06], [0, 1, 0, .07]])
        assert np.allclose(pair.get_fdata()[..., 0], 100)
        if not os.environ.get('TEST_SPATIAL_REVERSE'):
            assert np.allclose(pair.get_fdata()[..., 1], 90)
    reference = nib.load('INPUTS/b0.nii.gz')
    save(np.ones(reference.shape[:3]), 'INPUTS/b0.nii.gz', 'OUTPUTS/topup_fieldcoef.nii.gz')
    Path('OUTPUTS/topup_movpar.txt').write_text('0 0 0 0 0 0\n' * 2)
elif name == 'bet':
    image = nib.load(args[0])
    save(image.get_fdata() > 0, args[0], args[1][:-7] + '_mask.nii.gz')
elif name == 'fslmaths':
    image = nib.load(args[0])
    data = image.get_fdata()
    save(data.mean(axis=3) if data.ndim == 4 else data, args[0], args[-1])
elif name == 'fslmerge':
    save(np.stack([nib.load(path).get_fdata() for path in args[2:]], axis=3), args[2], args[1])
elif name == 'eddy':
    image = nib.load(option('--imain'))
    factor = 2 if Path.cwd().name == 'reversepe' else 1
    save(image.get_fdata() * factor, option('--imain'), option('--out') + '.nii.gz')
    bvecs = np.loadtxt(option('--bvecs'))
    if factor == 2:
        bvecs = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]]) @ bvecs
    np.savetxt(option('--out') + '.eddy_rotated_bvecs', bvecs)
    Path(option('--out') + '.eddy_outlier_map').write_text('Slice outlier map\n' + ('0 ' * image.shape[2] + '\n') * image.shape[3])
elif name == 'dwibiascorrect':
    subprocess.run(['mrconvert', args[1], args[2], '-force', '-quiet'], check=True)
elif name == 'flirt':
    if '-omat' in args:
        np.savetxt(value('-omat'), np.eye(4))
    if '-out' in args:
        shutil.copyfile(value('-in'), value('-out'))
elif name == 'transformconvert':
    np.savetxt(args[-1], np.eye(4))
elif name == 'antsRegistrationSyNQuick.sh':
    np.savetxt(value('-o') + '0GenericAffine.mat', np.eye(4))
    shutil.copyfile(value('-m'), value('-o') + 'Warped.nii.gz')
elif name == 'antsApplyTransforms':
    shutil.copyfile(value('-i'), value('-o'))
else:
    raise AssertionError(name)
'''
        for name in ("module", "singularity", "topup", "fslmaths", "fslmerge", "bet", "eddy", "dwibiascorrect",
                     "flirt", "transformconvert", "antsRegistrationSyNQuick.sh", "antsApplyTransforms", "sbatch"):
            path = stub_dir / name
            path.write_text(stub)
            path.chmod(0o755)
        self.env["PATH"] = str(stub_dir) + os.pathsep + self.env["PATH"]

    def run_preprocessing(self, method=None, reverse=None):
        args = ["bash", str(PREPROCESS), str(self.session)]
        if method:
            args.append(method)
        if reverse:
            args.append(str(reverse))
        # Running outside the session also checks that paths are explicit.
        return subprocess.run(args, cwd=self.root, env=self.env, capture_output=True, text=True)

    def commands(self, name):
        path = Path(self.env["TEST_COMMAND_LOG"])
        return [row for line in path.read_text().splitlines() if (row := json.loads(line))[0] == name]

    def test_switching_keeps_saved_variants_and_activates_matching_outputs(self):
        result = self.run_preprocessing()  # Existing invocation still selects Synb0.
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        filename = "sub-001_desc-preproc_dwi.nii.gz"
        saved_synb0 = self.dwi / "preprocessing/synb0" / filename
        before = saved_synb0.read_bytes()
        result = self.run_preprocessing("reversepe")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        saved_reverse = self.dwi / "preprocessing/reversepe" / filename
        reverse_before = saved_reverse.read_bytes()
        np.testing.assert_allclose(nib.load(saved_reverse).get_fdata(), nib.load(saved_synb0).get_fdata() * 2)
        self.assertEqual((self.dwi / filename).read_bytes(), saved_reverse.read_bytes())
        np.testing.assert_allclose(np.loadtxt(self.dwi / "sub-001_desc-preproc_dwi.bvec"),
                                   np.loadtxt(saved_reverse.parent / "eddy_unwarped_images.eddy_rotated_bvecs"), atol=1e-7)
        self.assertEqual(saved_synb0.read_bytes(), before)
        self.assertFalse((self.dwi / filename).samefile(saved_reverse))
        for method, factor in (("synb0", 1), ("reversepe", 2)):
            folder = self.dwi / "preprocessing" / method
            np.testing.assert_allclose(nib.load(folder / "mean_b0_final.nii.gz").get_fdata(), 100 * factor)
            np.testing.assert_allclose(np.loadtxt(folder / "sub-001_desc-preproc_dwi.bval"), [0] + [1000] * 6)
        active_anat = self.session / "anat/sub-001_T1_in_dwi_space.nii.gz"
        self.assertEqual(active_anat.read_bytes(), (saved_reverse.parent / active_anat.name).read_bytes())
        # Make the active mask wrong, then verify that switching restores the selected mask too.
        (self.dwi / "sub-001_desc-resampled_bet.mif").write_text("obsolete mask")
        result = self.run_preprocessing("synb0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.dwi / filename).read_bytes(), saved_synb0.read_bytes())
        self.assertEqual(saved_reverse.read_bytes(), reverse_before)
        np.testing.assert_allclose(np.loadtxt(self.dwi / "sub-001_desc-preproc_dwi.bvec"),
                                   np.loadtxt(saved_synb0.parent / "eddy_unwarped_images.eddy_rotated_bvecs"), atol=1e-7)
        self.assertEqual((self.dwi / "sub-001_desc-resampled_bet.mif").read_bytes(),
                         (saved_synb0.parent / "sub-001_desc-resampled_bet.mif").read_bytes())
        self.assertIn("SDC_METHOD: synb0", (self.dwi / "sub-001_desc-preprocessing_info.txt").read_text())
        self.assertEqual(len(self.commands("eddy")), 2)
        self.assertEqual(len(self.commands("topup")), 1)
        self.assertEqual(len(self.commands("singularity")), 1)

    def test_failed_field_estimation_keeps_active_results(self):
        active = self.dwi / "sub-001_desc-preproc_dwi.nii.gz"
        active.write_bytes(b"previous successful result")
        self.env["TEST_FAIL_TOPUP"] = "1"
        result = self.run_preprocessing("reversepe")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(active.read_bytes(), b"previous successful result")
        self.assertFalse(self.commands("eddy"))

    def test_reversepe_needs_no_synb0_container_and_accepts_explicit_b0(self):
        Path(self.env["SYNB0_SIF"]).unlink()
        result = self.run_preprocessing("reversepe", self.reverse)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.commands("singularity"))
        regrids = [row for row in self.commands("mrtransform") if row[2] == "INPUTS/reverse_b0_native.nii.gz"]
        self.assertFalse(regrids)

    def test_reverse_b0_is_regridded_in_scanner_coordinates_on_an_odd_dwi_grid(self):
        # A larger, shifted, rotated reverse-PE FOV represents BG391's mismatch.
        dwi = nib.load(self.raw)
        nib.save(nib.Nifti1Image(dwi.get_fdata()[:, :, :7, :], dwi.affine), self.raw)
        for name in ("Diff.mif", "Diff_den.mif", "Diff_den_gibbs.mif"):
            subprocess.run(["mrconvert", str(self.raw), str(self.dwi / name), "-fslgrad",
                            str(self.dwi / "sub-001_dwi.bvec"), str(self.dwi / "sub-001_dwi.bval"), "-force"],
                           env=self.env, capture_output=True, check=True)
        angle = np.deg2rad(1.2)
        rotation = np.array([[np.cos(angle), -np.sin(angle), 0],
                             [np.sin(angle), np.cos(angle), 0], [0, 0, 1]])
        affine = np.eye(4)
        affine[:3, :3] = rotation @ np.diag([-2., 2., 2.])
        affine[:3, 3] = [4, -4, -4]
        voxels = np.indices((12, 12, 12)).reshape(3, -1)
        world = affine[:3, :3] @ voxels + affine[:3, 3, None]
        center = np.array([-7, 7, 6])[:, None]
        signal = (90 * np.exp(-np.sum((world - center)**2, axis=0) / 72)).reshape(12, 12, 12)
        volumes = np.stack([signal, signal * 1.2], axis=3)
        nib.save(nib.Nifti1Image(volumes.astype(np.float32), affine), self.reverse)
        original_bytes = self.reverse.read_bytes()
        self.env["TEST_SPATIAL_REVERSE"] = "1"
        result = self.run_preprocessing("reversepe")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        inputs = self.dwi / "preprocessing/reversepe/INPUTS"
        native = nib.load(inputs / "reverse_b0_native.nii.gz")
        corrected = nib.load(inputs / "reverse_b0.nii.gz")
        reference = nib.load(inputs / "b0.nii.gz")
        self.assertEqual(native.shape, (12, 12, 12))
        np.testing.assert_allclose(native.get_fdata(), signal * 1.1, rtol=1e-6)
        self.assertEqual(corrected.shape, (8, 8, 7))
        np.testing.assert_allclose(corrected.affine, reference.affine, atol=1e-5)
        target_voxels = np.indices(corrected.shape).reshape(3, -1)
        target_world = reference.affine[:3, :3] @ target_voxels + reference.affine[:3, 3, None]
        expected = (99 * np.exp(-np.sum((target_world - center)**2, axis=0) / 72)).reshape(corrected.shape)
        # Verify interpolation of actual signal, rather than a header-only edit.
        np.testing.assert_allclose(corrected.get_fdata()[2:-2, 2:-2, 2:-2],
                                   expected[2:-2, 2:-2, 2:-2], atol=0.4)
        self.assertTrue(np.all(corrected.get_fdata() >= 0))
        self.assertEqual(self.reverse.read_bytes(), original_bytes)
        self.assertIn("REGRID_REVERSE: yes", (inputs.parent / "sub-001_desc-preprocessing_info.txt").read_text())
        self.assertEqual(len(self.commands("topup")), 1)
        self.assertEqual(len(self.commands("eddy")), 1)

    def test_diffusion_weighted_reverse_series_is_rejected_before_regridding(self):
        self.reverse.with_name("sub-001_acq-inverted_b0.bval").write_text("0 1000\n")
        result = self.run_preprocessing("reversepe")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must contain only B0 volumes", result.stderr)
        self.assertFalse(self.commands("topup"))

    def test_batch_launcher_passes_method_and_skips_sessions_without_reverse_b0(self):
        # Missing inputs in another subject should not abort the whole cohort.
        (self.root / "bids/sub-002/ses-1/dwi").mkdir(parents=True)
        result = subprocess.run(["bash", str(LAUNCHER), str(self.root / "bids"), "reversepe"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.commands("sbatch")[0][-2:], [str(self.session), "reversepe"])
        # The standard fmap EPI layout is supported as an alternative.
        fmap_reverse = self.session / "fmap/sub-001_dir-PA_epi.nii.gz"
        self.reverse.rename(fmap_reverse)
        self.reverse_json.rename(self.session / "fmap/sub-001_dir-PA_epi.json")
        result = subprocess.run(["bash", str(LAUNCHER), str(self.root / "bids"), "reversepe"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.commands("sbatch")), 2)
        fmap_reverse.unlink()
        result = subprocess.run(["bash", str(LAUNCHER), str(self.root / "bids"), "reversepe"],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Total jobs submitted: 0", result.stdout)
        self.assertEqual(len(self.commands("sbatch")), 2)


if __name__ == "__main__":
    unittest.main()
