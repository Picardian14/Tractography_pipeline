#!/bin/bash
#
# Submit stages 3 (deconvolution) through 6 (parcellation) as one MSMT-CSD
# Slurm workflow.
#
# Usage:
#   ./scripts/3_to_6_msmt.sh [BIDS folder name]
#
# The optional folder name has the same meaning as in paths_config.sh and
# defaults to "doc_data". BIDS_ROOT and the other path variables may also be
# overridden through the environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/paths_config.sh" "${1:-doc_data}"

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

subjects=()
response_ids=()
declare -A response_id tissue_id recon_id

for subject_dir in "$BIDS_ROOT"/sub-*; do
    [ -d "$subject_dir/dwi" ] || continue
    subject_id=$(basename "$subject_dir")
    subjects+=("$subject_id")

    response_id["$subject_id"]=$(submit_job "dwi2response for $subject_id" \
        --job-name="dwi2resp-$subject_id" \
        --output="$OUTPUT_DIR/${subject_id}-dwi2resp-%j.out.txt" \
        --error="$OUTPUT_DIR/${subject_id}-dwi2resp-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        "$dwi2response_job" "$subject_dir" "$PIPELINE_ROOT")
    response_ids+=("${response_id[$subject_id]}")

    # Tissue segmentation needs the .mif produced during dwi2response, but it
    # does not need to wait for the cohort response mean.
    if [ -d "$subject_dir/anat" ]; then
        tissue_id["$subject_id"]=$(submit_job "5TT segmentation for $subject_id" \
            --dependency="afterok:${response_id[$subject_id]}" \
            --job-name="5tt-$subject_id" \
            --output="$OUTPUT_DIR/${subject_id}-5tt-%j.out.txt" \
            --error="$OUTPUT_DIR/${subject_id}-5tt-%j.err.txt" \
            --chdir="$subject_dir/dwi" \
            --mem=16G --time=48:00:00 \
            "$tissue_job" "$subject_dir" "$PIPELINE_ROOT")

        # FreeSurfer is independent of deconvolution and can run immediately.
        recon_id["$subject_id"]=$(submit_job "recon-all for $subject_id" \
            --job-name="recon_all-$subject_id" \
            --output="$OUTPUT_DIR/${subject_id}-recon_all-%j.out.txt" \
            --error="$OUTPUT_DIR/${subject_id}-recon_all-%j.err.txt" \
            --chdir="$subject_dir/anat" \
            --mem=64G --time=24:00:00 \
            "$recon_all_job" "$subject_dir" "$PIPELINE_ROOT")
    fi
done

if [ "${#subjects[@]}" -eq 0 ]; then
    echo "No subjects with a dwi directory found under $BIDS_ROOT." >&2
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
    "$responsemean_job" "$PIPELINE_ROOT")

for subject_id in "${subjects[@]}"; do
    subject_dir="$BIDS_ROOT/$subject_id"

    msmt_id=$(submit_job "MSMT-CSD for $subject_id" \
        --dependency="afterok:${mean_id}" \
        --job-name="msmt-csd-$subject_id" \
        --output="$OUTPUT_DIR/${subject_id}-msmt-csd-%j.out.txt" \
        --error="$OUTPUT_DIR/${subject_id}-msmt-csd-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        "$msmt_csd_job" "$subject_dir" "$PIPELINE_ROOT")

    if [ -z "${tissue_id[$subject_id]:-}" ]; then
        echo "Skipping tractography/parcellation for $subject_id: no anat directory." >&2
        continue
    fi

    tck_id=$(submit_job "MSMT tractography for $subject_id" \
        --dependency="afterok:${msmt_id}:${tissue_id[$subject_id]}" \
        --job-name="tck-msmt-$subject_id" \
        --output="$OUTPUT_DIR/${subject_id}-tck-msmt-%j.out.txt" \
        --error="$OUTPUT_DIR/${subject_id}-tck-msmt-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        --mem=16G --time=12:00:00 \
        "$tckgen_job" "$subject_dir" "$PIPELINE_ROOT")

    submit_job "MSMT parcellation for $subject_id" \
        --dependency="afterok:${tck_id}:${recon_id[$subject_id]}" \
        --job-name="parcellate-msmt-$subject_id" \
        --output="$OUTPUT_DIR/${subject_id}-parcellate-msmt-%j.out.txt" \
        --error="$OUTPUT_DIR/${subject_id}-parcellate-msmt-%j.err.txt" \
        --chdir="$subject_dir/dwi" \
        --mem=32G --time=24:00:00 \
        "$parcellate_job" "$subject_dir" "$PIPELINE_ROOT" >/dev/null
done

echo "MSMT workflow submitted for ${#subjects[@]} subject(s)."
echo "Cohort response-mean barrier job: $mean_id"
