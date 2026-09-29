#!/bin/bash
#
# Submit stages 3 (deconvolution) through 6 (parcellation) as one MSMT-CSD
# Slurm workflow.
#
# Usage:
#   ./scripts/3_to_6_msmt.sh /absolute/path/to/bids

set -euo pipefail

workflow_start_epoch=$(date +%s)
workflow_start_timestamp=$(date '+%Y-%m-%d %H:%M:%S %z')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

BIDS_ROOT="$(readlink -f "$1")"
OUTPUT_DIR="${OUTPUT_DIR:-${PIPELINE_ROOT}/outputs}"
FREESURFER_SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-${PIPELINE_ROOT}/freesurfer}"
workflow_timing_log="${WORKFLOW_TIMING_LOG:-${OUTPUT_DIR}/3_to_6_msmt-${workflow_start_epoch}.timing.log}"
workflow_timing_log=$(readlink -m "$workflow_timing_log")

mkdir -p "$OUTPUT_DIR" "$FREESURFER_SUBJECTS_DIR"

dwi2response_job="${DWI2RESPONSE_JOB:-${SCRIPT_DIR}/3_deconvolution/dwi2response.sh}"
responsemean_job="${RESPONSEMEAN_JOB:-${SCRIPT_DIR}/3_deconvolution/2_responsemean.sh}"
msmt_csd_job="${MSMT_CSD_JOB:-${SCRIPT_DIR}/3_deconvolution/msmt_csd.sh}"
tissue_job="${TISSUE_JOB:-${SCRIPT_DIR}/4_segment5tt/tissue_job.sh}"
tckgen_job="${TCKGEN_MSMT_JOB:-${SCRIPT_DIR}/5_tractography/tckgen_msmt_job.sh}"
recon_all_job="${RECON_ALL_JOB:-${SCRIPT_DIR}/6_parcellation/recon_all_job.sh}"
parcellate_job="${PARCELLATE_MSMT_JOB:-${SCRIPT_DIR}/6_parcellation/parcellate_msmt_job.sh}"

for job_script in \
    "$dwi2response_job" "$responsemean_job" "$msmt_csd_job" "$tissue_job" \
    "$tckgen_job" "$recon_all_job" "$parcellate_job"; do
    if [ ! -f "$job_script" ]; then
        echo "Job script not found: $job_script" >&2
        exit 1
    fi
done

if ! command -v sbatch >/dev/null 2>&1; then
    echo "sbatch is not available in PATH." >&2
    exit 1
fi

printf 'MSMT workflow started: %s\n' "$workflow_start_timestamp" | tee "$workflow_timing_log"
echo "Workflow timing log: $workflow_timing_log"

# Print progress to stderr so command substitution receives only the job ID.
submit_job() {
    local description=$1
    shift
    local submission job_id
    submission=$(sbatch --parsable "$@")
    job_id=${submission%%;*}
    if [[ ! "$job_id" =~ ^[0-9]+([_.][0-9]+)?$ ]]; then
        echo "Could not parse Slurm job ID from: $submission" >&2
        exit 1
    fi
    echo "Submitted ${description}: ${job_id}" >&2
    printf '%s\n' "$job_id"
}

sessions=()
response_ids=()
declare -A session_path response_id tissue_id recon_id
parcellation_count=0

for session_dir in "$BIDS_ROOT"/sub-*/ses-*; do
    [ -d "$session_dir/dwi" ] || continue
    subject_id=$(basename "$(dirname "$session_dir")")
    session_id=$(basename "$session_dir")
    analysis_id="${subject_id}_${session_id}"
    sessions+=("$analysis_id")
    session_path["$analysis_id"]="$session_dir"

    response_id["$analysis_id"]=$(submit_job "dwi2response for $analysis_id" \
        --job-name="dwi2resp-$analysis_id" \
        --output="$OUTPUT_DIR/${analysis_id}-dwi2resp-%j.out.txt" \
        --error="$OUTPUT_DIR/${analysis_id}-dwi2resp-%j.err.txt" \
        --chdir="$session_dir/dwi" \
        "$dwi2response_job" "$session_dir")
    response_ids+=("${response_id[$analysis_id]}")

    # Tissue segmentation needs the .mif produced during dwi2response, but it
    # does not need to wait for the cohort response mean.
    if [ -d "$session_dir/anat" ]; then
        tissue_id["$analysis_id"]=$(submit_job "5TT segmentation for $analysis_id" \
            --dependency="afterok:${response_id[$analysis_id]}" \
            --job-name="5tt-$analysis_id" \
            --output="$OUTPUT_DIR/${analysis_id}-5tt-%j.out.txt" \
            --error="$OUTPUT_DIR/${analysis_id}-5tt-%j.err.txt" \
            --chdir="$session_dir/dwi" \
            --mem=16G --time=48:00:00 \
            "$tissue_job" "$session_dir")

        # FreeSurfer is independent of deconvolution and can run immediately.
        recon_id["$analysis_id"]=$(submit_job "recon-all for $analysis_id" \
            --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT" \
            --job-name="recon_all-$analysis_id" \
            --output="$OUTPUT_DIR/${analysis_id}-recon_all-%j.out.txt" \
            --error="$OUTPUT_DIR/${analysis_id}-recon_all-%j.err.txt" \
            --chdir="$session_dir/anat" \
            --mem=64G --time=24:00:00 \
            "$recon_all_job" "$session_dir")
    fi
done

if [ "${#sessions[@]}" -eq 0 ]; then
    echo "No sessions with a dwi directory found under $BIDS_ROOT." >&2
    exit 1
fi

response_dependency=$(IFS=:; echo "${response_ids[*]}")
mean_id=$(submit_job "cohort response mean" \
    --dependency="afterok:${response_dependency}" \
    --job-name="responsemean-msmt" \
    --output="$OUTPUT_DIR/responsemean-msmt-%j.out.txt" \
    --error="$OUTPUT_DIR/responsemean-msmt-%j.err.txt" \
    --chdir="$BIDS_ROOT" \
    --cpus-per-task=1 --mem=4G --time=01:00:00 \
    "$responsemean_job" "$BIDS_ROOT")

for analysis_id in "${sessions[@]}"; do
    session_dir=${session_path[$analysis_id]}

    msmt_id=$(submit_job "MSMT-CSD for $analysis_id" \
        --dependency="afterok:${mean_id}" \
        --job-name="msmt-csd-$analysis_id" \
        --output="$OUTPUT_DIR/${analysis_id}-msmt-csd-%j.out.txt" \
        --error="$OUTPUT_DIR/${analysis_id}-msmt-csd-%j.err.txt" \
        --chdir="$session_dir/dwi" \
        "$msmt_csd_job" "$session_dir")

    if [ -z "${tissue_id[$analysis_id]:-}" ]; then
        echo "Skipping tractography/parcellation for $analysis_id: no anat directory." >&2
        continue
    fi

    tck_id=$(submit_job "MSMT tractography for $analysis_id" \
        --dependency="afterok:${msmt_id}:${tissue_id[$analysis_id]}" \
        --job-name="tck-msmt-$analysis_id" \
        --output="$OUTPUT_DIR/${analysis_id}-tck-msmt-%j.out.txt" \
        --error="$OUTPUT_DIR/${analysis_id}-tck-msmt-%j.err.txt" \
        --chdir="$session_dir/dwi" \
        --mem=16G --time=12:00:00 \
        "$tckgen_job" "$session_dir")

    submit_job "MSMT parcellation for $analysis_id" \
        --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT",WORKFLOW_START_EPOCH="$workflow_start_epoch",WORKFLOW_TIMING_LOG="$workflow_timing_log" \
        --dependency="afterok:${tck_id}:${recon_id[$analysis_id]}" \
        --job-name="parcellate-msmt-$analysis_id" \
        --output="$OUTPUT_DIR/${analysis_id}-parcellate-msmt-%j.out.txt" \
        --error="$OUTPUT_DIR/${analysis_id}-parcellate-msmt-%j.err.txt" \
        --chdir="$session_dir/dwi" \
        --mem=32G --time=24:00:00 \
        "$parcellate_job" "$session_dir" >/dev/null
    ((parcellation_count += 1))
done

echo "MSMT workflow submitted for ${#sessions[@]} session(s)."
echo "Cohort response-mean barrier job: $mean_id"
if ((parcellation_count > 0)); then
    echo "Successful parcellation completion(s) will be appended to $workflow_timing_log."
else
    printf 'No MSMT parcellation jobs were submitted.\n' | tee -a "$workflow_timing_log"
fi
