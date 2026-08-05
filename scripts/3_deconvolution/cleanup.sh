#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: cleanup.sh [--scope SCOPE] [--dry-run] [--yes] /absolute/path/to/bids

Remove files produced by Stage 3 so that all or part of deconvolution can be
run again.

Scopes:
  all           All Stage 3 outputs (default)
  response      Subject response-estimation outputs
  responsemean  Cohort and subject mean-response outputs
  ss3t          Subject SS3T FOD outputs
  msmt          Subject MSMT-CSD FOD outputs

Options:
  -n, --dry-run  List files without removing them
  -y, --yes      Remove files without an interactive confirmation
  -h, --help     Show this help
EOF
}

scope=all
dry_run=false
assume_yes=false
bids_argument=

while (($# > 0)); do
    case "$1" in
        --scope)
            if (($# < 2)); then
                echo "--scope requires a value." >&2
                usage >&2
                exit 2
            fi
            scope=$2
            shift 2
            ;;
        -n|--dry-run)
            dry_run=true
            shift
            ;;
        -y|--yes)
            assume_yes=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            if (($# != 1)) || [[ -n "$bids_argument" ]]; then
                usage >&2
                exit 2
            fi
            bids_argument=$1
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$bids_argument" ]]; then
                echo "Only one BIDS root may be specified." >&2
                usage >&2
                exit 2
            fi
            bids_argument=$1
            shift
            ;;
    esac
done

case "$scope" in
    all|response|responsemean|ss3t|msmt) ;;
    *)
        echo "Unknown scope: $scope" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ -z "$bids_argument" || ! -d "$bids_argument" ]]; then
    echo "A valid BIDS root is required." >&2
    usage >&2
    exit 2
fi

BIDS_ROOT=$(readlink -f "$bids_argument")
if [[ "$BIDS_ROOT" == / ]]; then
    echo "Refusing to use the filesystem root as the BIDS root." >&2
    exit 2
fi

targets=()
add_target() {
    local path=$1
    if [[ -e "$path" || -L "$path" ]]; then
        targets+=("$path")
    fi
}

if [[ "$scope" == all || "$scope" == responsemean ]]; then
    for tissue in wm gm csf; do
        add_target "$BIDS_ROOT/desc-meanDhollander_response-${tissue}.txt"
    done
fi

subject_count=0
for subject_dir in "$BIDS_ROOT"/sub-*; do
    [[ -d "$subject_dir/dwi" ]] || continue
    ((subject_count += 1))
    subject=$(basename "$subject_dir")
    dwi_dir="$subject_dir/dwi"

    if [[ "$scope" == all || "$scope" == response ]]; then
        add_target "$dwi_dir/${subject}_desc-preproc_dwi.mif"
        add_target "$dwi_dir/${subject}_desc-hdbet_T1w_bet.mif"
        add_target "$dwi_dir/${subject}_desc-resampled_bet.mif"
        for tissue in wm gm csf; do
            add_target "$dwi_dir/${subject}_desc-dhollander_response-${tissue}.txt"
        done
        add_target "$dwi_dir/${subject}_desc-dhollander_voxels.mif"
    fi

    if [[ "$scope" == all || "$scope" == responsemean ]]; then
        for tissue in wm gm csf; do
            add_target "$dwi_dir/${subject}_desc-meanDhollander_response-${tissue}.txt"
        done
    fi

    if [[ "$scope" == all || "$scope" == ss3t ]]; then
        for tissue in wm gm csf; do
            add_target "$dwi_dir/${subject}_model-ss3t_fod-${tissue}.mif"
            add_target "$dwi_dir/${subject}_model-ss3t_desc-normalized_fod-${tissue}.mif"
        done
        add_target "$dwi_dir/${subject}_model-ss3t_vf.mif"
    fi

    if [[ "$scope" == all || "$scope" == msmt ]]; then
        for tissue in wm gm csf; do
            add_target "$dwi_dir/${subject}_model-msmt_fod-${tissue}.mif"
            add_target "$dwi_dir/${subject}_model-msmt_desc-normalized_fod-${tissue}.mif"
        done
        add_target "$dwi_dir/${subject}_model-msmt_vf.mif"
    fi
done

if ((subject_count == 0)); then
    echo "No subjects with a dwi directory found under $BIDS_ROOT." >&2
    exit 1
fi

if ((${#targets[@]} == 0)); then
    echo "No existing Stage 3 files matched scope '$scope' under $BIDS_ROOT."
    exit 0
fi

printf "Stage 3 cleanup scope: %s\n" "$scope"
printf "BIDS root: %s\n" "$BIDS_ROOT"
printf "Files matched: %d\n" "${#targets[@]}"
for target in "${targets[@]}"; do
    printf '  %s\n' "${target#"$BIDS_ROOT"/}"
done

if [[ "$dry_run" == true ]]; then
    echo "Dry run: no files were removed."
    exit 0
fi

if [[ "$assume_yes" != true ]]; then
    printf "Type 'delete' to remove these files: "
    if ! read -r confirmation || [[ "$confirmation" != delete ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

for target in "${targets[@]}"; do
    rm -f -- "$target"
done
printf "Removed %d Stage 3 file(s).\n" "${#targets[@]}"
