"""Check atlas selection and Slurm dependencies without submitting real jobs."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
COMBINED_SUBMIT = REPO / "scripts/6_parcellation/2_run_parcellate_cortico_subcortical_jobs.sh"


class AtlasSubmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bids = self.root / "test bids"
        self.session = self.bids / "sub-001/ses-1"
        (self.session / "dwi").mkdir(parents=True)
        (self.session / "anat").mkdir()
        (self.bids / "sub-002/ses-1/anat").mkdir(parents=True)
        self.log = self.root / "submissions.jsonl"
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "sbatch"
        stub.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
log = Path(os.environ['SUBMISSION_LOG'])
count = len(log.read_text().splitlines()) if log.exists() else 0
with log.open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\\n')
print(1001 + count)
""")
        stub.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("BASH_FUNC_") and key not in {
                        "ATLAS_LABEL_NAME", "SUBCORTICAL_LABEL_NAME", "ATLAS_DIR", "ATLAS_ROOT", "MODEL",
                        "PARCELLATE_MSMT_JOB", "PARCELLATE_SS3T_JOB", "PARCELLATE_CORTICO_SUBCORTICAL_JOB"}}
        self.env.update(PATH=str(bin_dir) + os.pathsep + self.env["PATH"], SUBMISSION_LOG=str(self.log),
                        OUTPUT_DIR=str(self.root / "logs"), FREESURFER_SUBJECTS_DIR=str(self.root / "freesurfer"))

    def run_launcher(self, script, *args):
        self.log.unlink(missing_ok=True)
        result = subprocess.run(["bash", str(script), *map(str, args)], env=self.env, text=True, capture_output=True)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_workflows_select_combined_job_and_preserve_dependencies(self):
        self.env.update(ATLAS_LABEL_NAME="schaefer100-yeo7", SUBCORTICAL_LABEL_NAME="tians1")
        for model in ("msmt", "ss3t"):
            with self.subTest(model=model):
                result, calls = self.run_launcher(REPO / f"scripts/3_to_6_{model}.sh", self.bids,
                                                  "--atlas", "yan100_kong17", "--subcortical-atlas", "tians3")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(len(calls), 7)
                parc = calls[-1]
                self.assertTrue(parc[-2].endswith("/parcellate_cortico_subcortical_job.sh"))
                self.assertEqual(parc[-1], str(self.session))
                self.assertIn("--dependency=afterok:1006:1003", parc)
                self.assertIn("--dependency=afterok:1005:1002", calls[-2])
                exports = next(arg for arg in parc if arg.startswith("--export="))
                self.assertIn(f",MODEL={model},", exports)
                self.assertIn(",ATLAS_LABEL_NAME=yan100_kong17,", exports)
                self.assertIn(",SUBCORTICAL_LABEL_NAME=tians3,", exports)
                self.assertIn("WORKFLOW_TIMING_LOG=", exports)
                self.assertTrue(any("yan100_kong17-tians3" in arg for arg in parc if arg.startswith("--output=")))

    def test_workflows_keep_cortical_default_and_accept_atlas_alone(self):
        for model in ("msmt", "ss3t"):
            for atlas_args, expected in (((), "schaefer100-yeo7"), (("--atlas", "yan100_kong17"), "yan100_kong17")):
                with self.subTest(model=model, atlas=expected):
                    result, calls = self.run_launcher(REPO / f"scripts/3_to_6_{model}.sh", self.bids, *atlas_args)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(len(calls), 7)
                    self.assertTrue(calls[-1][-2].endswith(f"/parcellate_{model}_job.sh"))
                    exports = next(arg for arg in calls[-1] if arg.startswith("--export="))
                    self.assertIn(f",ATLAS_LABEL_NAME={expected},", exports)

    def test_dedicated_submitter_supports_defaults_and_session_overrides(self):
        result, calls = self.run_launcher(COMBINED_SUBMIT, self.bids)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(calls), 1)
        exports = next(arg for arg in calls[0] if arg.startswith("--export="))
        self.assertIn("ATLAS_LABEL_NAME=schaefer100-yeo7", exports)
        self.assertIn("SUBCORTICAL_LABEL_NAME=tians2", exports)
        self.env.update(MODEL="ss3t", ATLAS_LABEL_NAME="schaefer100-yeo7", SUBCORTICAL_LABEL_NAME="tians1")
        result, calls = self.run_launcher(COMBINED_SUBMIT, self.session, "--atlas", "yan100_kong17",
                                          "--subcortical-atlas", "tians3")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(calls), 1)
        exports = next(arg for arg in calls[0] if arg.startswith("--export="))
        self.assertIn("MODEL=ss3t", exports)
        self.assertIn("ATLAS_LABEL_NAME=yan100_kong17", exports)
        self.assertIn("SUBCORTICAL_LABEL_NAME=tians3", exports)
        self.assertEqual(calls[0][-1], str(self.session))

    def test_invalid_arguments_fail_before_any_submission(self):
        scripts = [COMBINED_SUBMIT, REPO / "scripts/3_to_6_msmt.sh", REPO / "scripts/3_to_6_ss3t.sh"]
        for script in scripts:
            for args in (("--atlas",), ("--atlas", "--subcortical-atlas", "tians2"),
                         ("--subcortical-atlas", ""), ("--unknown", "x"), ("--atlas", "does-not-exist")):
                with self.subTest(script=script.name, args=args):
                    result, calls = self.run_launcher(script, self.bids, *args)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
