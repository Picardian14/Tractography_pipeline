#!/bin/bash
# Run SS3T parcellation sequentially on this machine, without Slurm.
set -uo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
BIDS_ROOT="$(readlink -f "$1")"
NTHREADS="${NTHREADS:-4}"
if ! [[ "$NTHREADS" =~ ^[1-9][0-9]*$ ]]; then
    echo "NTHREADS must be a positive integer." >&2
    exit 2
fi
RUN_DIR="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs/parcellate-ss3t-local-$(date +%Y%m%d-%H%M%S)-$$}"
mkdir -p "$RUN_DIR" || exit 1
RUN_DIR="$(readlink -f "$RUN_DIR")"
parcellate_job="${PARCELLATE_SS3T_JOB:-${SCRIPT_DIR}/parcellate_ss3t_job.sh}"

# The job uses SLURM_CPUS_PER_TASK even when called directly with bash.
export SLURM_CPUS_PER_TASK="$NTHREADS" OMP_NUM_THREADS="$NTHREADS"
export MRTRIX_NTHREADS="$NTHREADS" ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="$NTHREADS"
# Structural parcellation does not need FSFAST. Its MATLAB startup check can
# otherwise exit under the job's set -eo pipefail before any processing starts.
export NO_FSFAST=1

printf 'analysis_id\texit_status\tstarted\tfinished\n' > "$RUN_DIR/status.tsv"
echo "Local SS3T parcellation on $(hostname), $NTHREADS threads per session"
echo "Logs and status: $RUN_DIR"
total=0
failed=0
for session_dir in "$BIDS_ROOT"/sub-*/ses-*; do
    [ -d "$session_dir/dwi" ] || continue
    subject_id=$(basename "$(dirname "$session_dir")")
    analysis_id="${subject_id}_$(basename "$session_dir")"
    started=$(date -Is)
    echo "Starting $analysis_id at $started"
    (
        cd "$session_dir/dwi" || exit 1
        bash "$parcellate_job" "$session_dir"
    ) > "$RUN_DIR/$analysis_id.log" 2>&1
    exit_status=$?
    finished=$(date -Is)
    printf '%s\t%d\t%s\t%s\n' "$analysis_id" "$exit_status" "$started" "$finished" >> "$RUN_DIR/status.tsv"
    total=$((total + 1))
    if [ "$exit_status" -ne 0 ]; then
        failed=$((failed + 1))
        echo "FAILED $analysis_id (exit $exit_status); see $RUN_DIR/$analysis_id.log" >&2
    else
        echo "Finished $analysis_id at $finished"
    fi
done

if [ "$total" -eq 0 ]; then
    echo "No sub-*/ses-*/dwi directories found in $BIDS_ROOT." >&2
    exit 1
fi
echo "Finished: $total sessions, $failed failed. Status: $RUN_DIR/status.tsv"
[ "$failed" -eq 0 ]
