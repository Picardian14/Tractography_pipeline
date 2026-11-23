"""Check routing, companion-file preservation, and safe organizer execution."""

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "scripts/1_before_preprocessing/2_organize_dcm2bids_helper.py"
)
spec = importlib.util.spec_from_file_location("organize_helper", SCRIPT)
organizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(organizer)


class OrganizeHelperTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.subject = self.root / "sub-123"
        self.helper = self.subject / "tmp_dcm2bids/helper"
        self.helper.mkdir(parents=True)
        self.add_series("001_T1", "T1 MPRAGE")
        self.add_series("002_DWI", "DIFF SMS", bvals="0 1000 1000", phase="j-")

    def add_series(self, prefix, description, bvals=None, phase=None, derived=False, image_type=None):
        metadata = {
            "SeriesDescription": description,
            "ImageType": image_type if image_type is not None else ["DERIVED" if derived else "ORIGINAL", "PRIMARY"],
        }
        if bvals is not None:
            metadata["ImageType"].append("DIFFUSION")
            (self.helper / f"{prefix}.bval").write_text(bvals)
            (self.helper / f"{prefix}.bvec").write_text("0 0 0\n0 0 0\n0 0 0\n")
        if phase:
            metadata["PhaseEncodingDirection"] = phase
        (self.helper / f"{prefix}.json").write_text(json.dumps(metadata))
        # The organizer only moves bytes; image decoding is outside its scope.
        (self.helper / f"{prefix}.nii.gz").write_bytes(prefix.encode())

    def destinations(self):
        moves, _, _ = organizer.plan_subject(self.subject, "1")
        return {str(source.relative_to(self.helper)): str(destination.relative_to(self.subject))
                for source, destination in moves}

    def test_inverted_b0_keeps_gradients_in_dwi(self):
        self.add_series("025_B0_INV", "B0 INV", bvals="0 0 0", phase="j")
        destinations = self.destinations()
        for extension in (".nii.gz", ".json", ".bval", ".bvec"):
            self.assertEqual(destinations[f"025_B0_INV{extension}"],
                             f"ses-1/dwi/sub-123_acq-inverted_b0{extension}")
        self.assertEqual(destinations["002_DWI.nii.gz"], "ses-1/dwi/sub-123_dwi.nii.gz")

    def test_named_inverted_b0_does_not_require_gradients(self):
        self.add_series("025_B0_INV", "B0 INV")
        destinations = self.destinations()
        self.assertEqual(destinations["025_B0_INV.nii.gz"],
                         "ses-1/dwi/sub-123_acq-inverted_b0.nii.gz")

    def test_phase_encoding_distinguishes_b0_references(self):
        self.add_series("020_reference", "DIFF reference", bvals="0 0", phase="j")
        self.add_series("021_reference", "DIFF reference", bvals="0 0", phase="j-")
        destinations = self.destinations()
        self.assertEqual(destinations["020_reference.nii.gz"],
                         "ses-1/dwi/sub-123_acq-inverted_b0.nii.gz")
        self.assertEqual(destinations["021_reference.nii.gz"], "ses-1/dwi/sub-123_b0.nii.gz")

    def test_other_modalities_and_repeated_acquisitions(self):
        self.add_series("007_FLAIR", "AX 3D FLAIR")
        self.add_series("008_FLAIR_ND", "AX 3D FLAIR_ND", derived=True)
        self.add_series("021_SWI", "SWI_Images")
        self.add_series("022_T2", "AX T2")
        self.add_series("023_unknown", "Custom scan (test)")
        self.add_series("024_localizer", "Localizer")
        (self.helper / "007_FLAIR.extra.json").write_text("{}")
        destinations = self.destinations()
        expected = {
            "007_FLAIR": "run-1_FLAIR", "008_FLAIR_ND": "run-2_FLAIR",
            "021_SWI": "SWI", "022_T2": "T2w", "023_unknown": "acq-Customscantest_image",
        }
        for prefix, suffix in expected.items():
            for extension in (".nii.gz", ".json"):
                self.assertEqual(destinations[f"{prefix}{extension}"],
                                 f"ses-1/other/sub-123_{suffix}{extension}")
        self.assertEqual(destinations["007_FLAIR.extra.json"],
                         "ses-1/other/sub-123_run-1_FLAIR.extra.json")
        self.assertNotIn("024_localizer.nii.gz", destinations)

    def test_repeated_inverted_b0_acquisitions(self):
        for prefix in ("025_B0_INV", "026_B0_INV"):
            self.add_series(prefix, "B0 INV", bvals="0 0 0")
        destinations = self.destinations()
        for run, prefix in enumerate(("025_B0_INV", "026_B0_INV"), start=1):
            self.assertEqual(destinations[f"{prefix}.nii.gz"],
                             f"ses-1/dwi/sub-123_acq-inverted_run-{run}_b0.nii.gz")

    def test_dry_run_apply_and_rerun(self):
        self.add_series("025_B0_INV", "B0 INV", bvals="0 0 0")
        self.add_series("007_FLAIR", "AX 3D FLAIR")
        before = {p: p.read_bytes() for p in self.helper.iterdir()}
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.root)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, {p: p.read_bytes() for p in self.helper.iterdir()})
        self.assertFalse((self.subject / "ses-1").exists())

        destinations = self.destinations()
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.root), "--apply"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.helper.exists())
        for source, destination in destinations.items():
            self.assertEqual((self.subject / destination).read_bytes(), before[self.helper / source])
        moves, removals, _ = organizer.plan_subject(self.subject, "1")
        self.assertEqual((moves, removals), ([], []))

    def test_existing_destination_is_rejected_before_cleanup(self):
        self.add_series("025_B0_INV", "B0 INV", bvals="0 0 0")
        destination = self.subject / "ses-1/dwi/sub-123_acq-inverted_b0.nii.gz"
        destination.parent.mkdir(parents=True)
        destination.write_bytes(b"existing scan")
        with self.assertRaisesRegex(ValueError, "destination already exists"):
            organizer.plan_subject(self.subject, "1")
        self.assertEqual(destination.read_bytes(), b"existing scan")
        self.assertTrue(self.helper.is_dir())

    def test_session_suffix_overrides_fallback_session(self):
        for suffix in ("1", "2", "12"):
            with self.subTest(suffix=suffix):
                output, session = organizer.subject_session(self.root / f"sub-XX123_{suffix}", "9")
                self.assertEqual(output, self.root / "sub-XX123")
                self.assertEqual(session, suffix)
        self.assertEqual(organizer.subject_session(self.subject, "4"), (self.subject, "4"))
        moves, _, _ = organizer.plan_subject(self.subject, "4")
        self.assertTrue(all(destination.is_relative_to(self.subject / "ses-4")
                            for _, destination in moves))

    def test_two_sessions_share_subject_folder_and_keep_distinct_data(self):
        self.add_series("025_B0_INV", "B0 INV", bvals="0 0 0")
        self.add_series("007_FLAIR", "AX 3D FLAIR")
        first = self.root / "sub-123_1"
        second = self.root / "sub-123_2"
        self.subject.rename(first)
        shutil.copytree(first, second)
        second_t1 = second / "tmp_dcm2bids/helper/001_T1.nii.gz"
        second_t1.write_bytes(b"second session T1")
        before = {path: path.read_bytes() for folder in (first, second)
                  for path in folder.rglob("*") if path.is_file()}
        command = [sys.executable, str(SCRIPT), str(self.root), "--session-label", "9"]
        dry_run = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(dry_run.returncode, 0, dry_run.stdout + dry_run.stderr)
        self.assertFalse(self.subject.exists())
        self.assertTrue(all(path.read_bytes() == contents for path, contents in before.items()))

        result = subprocess.run([*command, "--apply"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(first.exists())
        self.assertFalse(second.exists())
        for session in ("1", "2"):
            session_dir = self.subject / f"ses-{session}"
            self.assertTrue((session_dir / "dwi/sub-123_dwi.nii.gz").is_file())
            self.assertTrue((session_dir / "dwi/sub-123_acq-inverted_b0.nii.gz").is_file())
            self.assertTrue((session_dir / "other/sub-123_FLAIR.nii.gz").is_file())
            self.assertTrue(all(path.name.startswith("sub-123_")
                                for path in session_dir.rglob("*") if path.is_file()))
        self.assertEqual((self.subject / "ses-1/anat/sub-123_T1w.nii.gz").read_bytes(), b"001_T1")
        self.assertEqual((self.subject / "ses-2/anat/sub-123_T1w.nii.gz").read_bytes(),
                         b"second session T1")
        self.assertFalse((self.subject / "ses-9").exists())
        rerun = subprocess.run([*command, "--apply"], capture_output=True, text=True)
        self.assertEqual(rerun.returncode, 0, rerun.stdout + rerun.stderr)

    def test_session_two_alone_can_be_rerun_and_keeps_unrelated_source_files(self):
        source = self.root / "sub-123_2"
        self.subject.rename(source)
        note = source / "notes.txt"
        note.write_text("keep this")
        command = [sys.executable, str(SCRIPT), str(self.root), "--apply"]
        for _ in range(2):
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(note.read_text(), "keep this")
        self.assertTrue((self.subject / "ses-2/dwi/sub-123_dwi.nii.gz").is_file())
        self.assertFalse((self.subject / "ses-1").exists())

    def test_previously_organized_suffixed_folder_is_migrated(self):
        # Simulate the earlier script's sub-123_2/ses-1/sub-123_2_* layout.
        initial = subprocess.run([sys.executable, str(SCRIPT), str(self.root), "--apply"],
                                 capture_output=True, text=True)
        self.assertEqual(initial.returncode, 0, initial.stdout + initial.stderr)
        for path in self.subject.rglob("*"):
            if path.is_file():
                path.rename(path.with_name(path.name.replace("sub-123_", "sub-123_2_", 1)))
        source = self.root / "sub-123_2"
        self.subject.rename(source)
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.root), "--apply"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(source.exists())
        self.assertEqual((self.subject / "ses-2/anat/sub-123_T1w.nii.gz").read_bytes(), b"001_T1")
        self.assertTrue((self.subject / "ses-2/dwi/sub-123_dwi.bvec").is_file())
        self.assertFalse((self.subject / "ses-1").exists())

    def test_existing_session_destination_is_not_overwritten(self):
        source = self.root / "sub-123_2"
        self.subject.rename(source)
        destination = self.subject / "ses-2/dwi/sub-123_dwi.nii.gz"
        destination.parent.mkdir(parents=True)
        destination.write_bytes(b"existing diffusion data")
        for extension in (".json", ".bval", ".bvec"):
            (destination.parent / f"sub-123_dwi{extension}").write_text("existing")
        anat = self.subject / "ses-2/anat"
        anat.mkdir()
        for extension in (".nii.gz", ".json"):
            (anat / f"sub-123_T1w{extension}").write_text("existing")
        with self.assertRaisesRegex(ValueError, "destination already exists"):
            organizer.plan_subject(source, "1")
        self.assertEqual(destination.read_bytes(), b"existing diffusion data")
        self.assertTrue((source / "tmp_dcm2bids/helper").is_dir())

    def test_scanner_normalized_t1w_is_used_when_original_is_absent(self):
        # These are the actual T1w ImageType flags exported for LE468/FT410.
        self.add_series("001_T1", "SAG T1 MPRAGE_ND", image_type=[
            "DERIVED", "PRIMARY", "M", "NORM", "ND", "FM", "FIL", "MFSPLIT", "MAGNITUDE",
        ])
        destinations = self.destinations()
        self.assertEqual(destinations["001_T1.nii.gz"], "ses-1/anat/sub-123_T1w.nii.gz")
        self.assertEqual(destinations["002_DWI.nii.gz"], "ses-1/dwi/sub-123_dwi.nii.gz")

    def test_original_t1w_is_preferred_over_scanner_reconstruction(self):
        self.add_series("003_T1_ND", "SAG T1 MPRAGE_ND", image_type=[
            "DERIVED", "PRIMARY", "M", "NORM", "ND", "MAGNITUDE",
        ])
        destinations = self.destinations()
        self.assertEqual(destinations["001_T1.nii.gz"], "ses-1/anat/sub-123_T1w.nii.gz")
        self.assertEqual(destinations["003_T1_ND.nii.gz"], "ses-1/other/sub-123_T1w.nii.gz")

    def test_original_secondary_dwi_is_accepted(self):
        # FH400's diffusion acquisition is ORIGINAL/SECONDARY, not DERIVED.
        self.add_series("002_DWI", "DIFF SMS", bvals="0 1000 1000", image_type=[
            "ORIGINAL", "SECONDARY", "DIFFUSION", "NONE", "ND", "NORM", "MFSPLIT",
        ])
        destinations = self.destinations()
        for extension in (".nii.gz", ".json", ".bval", ".bvec"):
            self.assertEqual(destinations[f"002_DWI{extension}"],
                             f"ses-1/dwi/sub-123_dwi{extension}")

    def test_arbitrary_derived_t1w_and_secondary_screenshots_remain_excluded(self):
        for image_type in (
            ["DERIVED", "PRIMARY", "M"],
            ["DERIVED", "SECONDARY", "M", "NORM", "ND"],
            ["ORIGINAL", "SECONDARY", "M"],
        ):
            with self.subTest(image_type=image_type):
                self.add_series("001_T1", "T1 MPRAGE", image_type=image_type)
                with self.assertRaisesRegex(ValueError, "no original T1w"):
                    organizer.plan_subject(self.subject, "1")

    def test_derived_diffusion_maps_are_not_selected_as_dwi(self):
        self.add_series("003_ADC", "DIFF ADC", bvals="0 1000 1000", derived=True)
        destinations = self.destinations()
        self.assertEqual(destinations["002_DWI.nii.gz"], "ses-1/dwi/sub-123_dwi.nii.gz")
        self.assertEqual(destinations["003_ADC.nii.gz"], "ses-1/other/sub-123_ADC.nii.gz")


if __name__ == "__main__":
    unittest.main()
