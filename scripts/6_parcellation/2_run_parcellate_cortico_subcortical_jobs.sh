#!/bin/bash
# Submit one cortico-subcortical job per session, or one specific session.
set -eo pipefail
if [ "$#" -lt 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids-or-session [--atlas NAME] [--subcortical-atlas NAME]" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
input_dir="$(readlink -f "$1")"
output="${OUTPUT_DIR:-$PIPELINE_ROOT/outputs}"
parcellate_job="${PARCELLATE_CORTICO_SUBCORTICAL_JOB:-$SCRIPT_DIR/parcellate_cortico_subcortical_job.sh}"
export MODEL="${MODEL:-msmt}"
export ATLAS_LABEL_NAME="${ATLAS_LABEL_NAME:-schaefer100-yeo7}"
export SUBCORTICAL_LABEL_NAME="${SUBCORTICAL_LABEL_NAME:-tians2}"
shift
while [ "$#" -gt 0 ]; do
    case "$1" in
        --atlas|--subcortical-atlas)
            if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "Missing atlas name after $1" >&2
                exit 2
            fi
            if [ "$1" = --atlas ]; then
                ATLAS_LABEL_NAME="$2"
            else
                SUBCORTICAL_LABEL_NAME="$2"
            fi
            shift 2
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
atlas_dir="${ATLAS_DIR:-${ATLAS_ROOT:-$PIPELINE_ROOT/templates_parcellations}/$ATLAS_LABEL_NAME}"
if [ ! -d "$atlas_dir" ]; then
    echo "Cortical atlas directory not found: $atlas_dir" >&2
    exit 2
fi
case "$MODEL" in msmt|ss3t) ;; *) echo "MODEL must be msmt or ss3t" >&2; exit 2 ;; esac
combined_atlas="${ATLAS_LABEL_NAME}-${SUBCORTICAL_LABEL_NAME}"

if [ -d "$input_dir/dwi" ]; then
    session_dirs=("$input_dir")
else
    session_dirs=("$input_dir"/sub-*/ses-*)
fi

mkdir -p "$output"
for session_dir in "${session_dirs[@]}"; do
    [ -d "$session_dir/dwi" ] || continue
    subject_id=$(basename "$(dirname "$session_dir")")
    session_id=$(basename "$session_dir")
    analysis_id="${subject_id}_${session_id}"
    echo "Submitting $analysis_id ($MODEL, $combined_atlas)"
    sbatch --job-name="parcellate-${MODEL}-${combined_atlas}-${analysis_id}" \
        --export=ALL,PIPELINE_ROOT="$PIPELINE_ROOT",MODEL="$MODEL",ATLAS_LABEL_NAME="$ATLAS_LABEL_NAME",SUBCORTICAL_LABEL_NAME="$SUBCORTICAL_LABEL_NAME" \
        --output="$output/${analysis_id}-parcellate-${MODEL}-${combined_atlas}-%j.out.txt" \
        --error="$output/${analysis_id}-parcellate-${MODEL}-${combined_atlas}-%j.err.txt" \
        --chdir="$session_dir/dwi" \
        --mem=32G --time=08:00:00 \
        "$parcellate_job" "$session_dir"
done
