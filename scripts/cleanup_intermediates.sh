#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: cleanup_intermediates.sh [OPTIONS] /absolute/path/to/bids

Remove intermediate files that are not consumed by later pipeline stages.
Final analysis products, raw BIDS inputs, and downstream inputs are preserved.

Options:
  --stage STAGES        Comma-separated stages to clean: 2,3,4,5,6,all
                        (default: all)
  --include-qc          Also remove files used only for visual QC
  --atlas NAME          Stage 6 atlas label (default: schaefer100-yeo7)
  --freesurfer-dir DIR  FreeSurfer SUBJECTS_DIR (default: repository/freesurfer)
  -n, --dry-run         List files without removing them
  -y, --yes             Remove files without interactive confirmation
  -h, --help            Show this help

The script cleans a stage for a session only when that stage's required final
outputs exist. It never removes the 10M tractogram, SIFT2 weights, normalized
WM FOD, registered 5TT/GMWMI, parcellation used for QC, or connectome outputs.
EOF
}

stages=all
include_qc=false
dry_run=false
assume_yes=false
atlas_name=schaefer100-yeo7
bids_argument=
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pipeline_root=$(cd "$script_dir/.." && pwd)
freesurfer_dir="${FREESURFER_SUBJECTS_DIR:-$pipeline_root/freesurfer}"

while (($# > 0)); do
    case "$1" in
        --stage)
            (($# >= 2)) || { echo "--stage requires a value." >&2; exit 2; }
            stages=$2
            shift 2
            ;;
        --include-qc)
            include_qc=true
            shift
            ;;
        --atlas)
            (($# >= 2)) || { echo "--atlas requires a value." >&2; exit 2; }
            atlas_name=$2
            shift 2
            ;;
        --freesurfer-dir)
            (($# >= 2)) || { echo "--freesurfer-dir requires a value." >&2; exit 2; }
            freesurfer_dir=$2
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
        -* )
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$bids_argument" ]]; then
                echo "Only one BIDS root may be specified." >&2
                exit 2
            fi
            bids_argument=$1
            shift
            ;;
    esac
done

if [[ -z "$bids_argument" || ! -d "$bids_argument" ]]; then
    echo "A valid BIDS root is required." >&2
    usage >&2
    exit 2
fi

BIDS_ROOT=$(readlink -f "$bids_argument")
freesurfer_dir=$(readlink -m "$freesurfer_dir")
if [[ "$BIDS_ROOT" == / || "$freesurfer_dir" == / ]]; then
    echo "Refusing to use the filesystem root as an input directory." >&2
    exit 2
fi

declare -A clean_stage=()
if [[ "$stages" == all ]]; then
    for stage in 2 3 4 5 6; do
        clean_stage[$stage]=true
    done
else
    IFS=',' read -r -a requested_stages <<< "$stages"
    for stage in "${requested_stages[@]}"; do
        case "$stage" in
            2|3|4|5|6) clean_stage[$stage]=true ;;
            *) echo "Unknown stage: $stage" >&2; usage >&2; exit 2 ;;
        esac
    done
fi

targets=()
declare -A target_seen=()
add_file() {
    local path=$1
    if [[ (-f "$path" || -L "$path") && -z "${target_seen[$path]:-}" ]]; then
        targets+=("$path")
        target_seen[$path]=true
    fi
}
add_tree_files() {
    local directory=$1
    [[ -d "$directory" ]] || return 0
    while IFS= read -r -d '' path; do
        add_file "$path"
    done < <(find "$directory" \( -type f -o -type l \) -print0)
}

session_count=0
skipped_count=0
for session_dir in "$BIDS_ROOT"/sub-*/ses-*; do
    [[ -d "$session_dir/dwi" ]] || continue
    ((session_count += 1))
    subject=$(basename "$(dirname "$session_dir")")
    session=$(basename "$session_dir")
    dwi_dir="$session_dir/dwi"
    anat_dir="$session_dir/anat"

    # Stage 2: retain the preprocessed DWI/gradients, b0 mask, DTI/FA outputs,
    # mean b0, anatomical derivatives, transforms, and registration QC images.
    if [[ -n "${clean_stage[2]:-}" ]]; then
        if [[ -f "$dwi_dir/${subject}_desc-preproc_dwi.mif" &&
              -f "$dwi_dir/${subject}_desc-preproc_dwi.nii.gz" &&
              -f "$dwi_dir/${subject}_desc-preproc_dwi.bval" &&
              -f "$dwi_dir/${subject}_desc-preproc_dwi.bvec" &&
              -f "$dwi_dir/${subject}_model-dti_FA.nii.gz" &&
              -f "$dwi_dir/mean_b0_final.nii.gz" &&
              -f "$anat_dir/${subject}_T1_in_dwi_space.nii.gz" ]]; then
            for name in Diff.mif Diff_den.mif Diff_den_gibbs.mif \
                mean_b0_AP.mif mean_b0_AP.nii.gz mean_b0_PA.mif \
                mean_b0_PA.nii.gz eddy_indices.txt Diff_eddy_in.nii.gz \
                Diff_preproc.mif Diff_preproc_unbiased.mif bias.mif; do
                add_file "$dwi_dir/$name"
            done
            add_file "$anat_dir/${subject}_desc-hdbet_T1w_bet.mif"
            add_tree_files "$dwi_dir/INPUTS"
            add_tree_files "$dwi_dir/OUTPUTS"
            for path in "$dwi_dir"/eddy_unwarped_images.*; do
                add_file "$path"
            done
            if [[ "$include_qc" == true ]]; then
                add_file "$dwi_dir/noise.mif"
                add_file "$dwi_dir/residual.mif"
            fi
        else
            printf 'Skipping Stage 2 for %s/%s: final preprocessed DWI set is incomplete.\n' \
                "$subject" "$session" >&2
            ((skipped_count += 1))
        fi
    fi

    # Stage 3: retain response text files for cohort reproducibility and the
    # normalized WM FOD consumed by tractography. Other tissue images are not
    # read by Stages 4--6.
    if [[ -n "${clean_stage[3]:-}" ]]; then
        stage3_complete=false
        for model in ss3t msmt; do
            if [[ -f "$dwi_dir/${subject}_model-${model}_desc-normalized_fod-wm.mif" ]]; then
                stage3_complete=true
                for tissue in wm gm csf; do
                    add_file "$dwi_dir/${subject}_model-${model}_fod-${tissue}.mif"
                done
                add_file "$dwi_dir/${subject}_model-${model}_desc-normalized_fod-gm.mif"
                add_file "$dwi_dir/${subject}_model-${model}_desc-normalized_fod-csf.mif"
                add_file "$dwi_dir/${subject}_model-${model}_vf.mif"
            fi
        done
        if [[ "$stage3_complete" == true ]]; then
            add_file "$dwi_dir/${subject}_desc-hdbet_T1w_bet.mif"
            if [[ "$include_qc" == true ]]; then
                add_file "$dwi_dir/${subject}_desc-resampled_bet.mif"
                add_file "$dwi_dir/${subject}_desc-dhollander_voxels.mif"
            fi
        else
            printf 'Skipping Stage 3 for %s/%s: no normalized WM FOD found.\n' \
                "$subject" "$session" >&2
            ((skipped_count += 1))
        fi
    fi

    # Stage 4: registered 5TT and GMWMI are the only files consumed by Stage 5.
    if [[ -n "${clean_stage[4]:-}" ]]; then
        if [[ -f "$dwi_dir/${subject}_desc-coreg_5tt.mif" &&
              -f "$dwi_dir/${subject}_desc-coreg_gmwmi.mif" ]]; then
            for name in "${subject}_T1w.mif" \
                "${subject}_desc-nocoreg_5tt.nii.gz" \
                "${subject}_desc-nocoreg_5tt_vol0.nii.gz" \
                "${subject}_from-T1w_to-dwi_rigid.mat" \
                "${subject}_from-T1w_to-dwi_rigid.txt" \
                "${subject}_desc-coreg_5tt.nii.gz"; do
                add_file "$dwi_dir/$name"
            done
            if [[ "$include_qc" == true ]]; then
                add_file "$dwi_dir/${subject}_desc-nocoreg_5tt.mif"
            fi
        else
            printf 'Skipping Stage 4 for %s/%s: registered 5TT/GMWMI set is incomplete.\n' \
                "$subject" "$session" >&2
            ((skipped_count += 1))
        fi
    fi

    # Stage 5: mu and fit coefficients are diagnostics; the full tractogram
    # and per-streamline weights remain available for connectome construction.
    if [[ -n "${clean_stage[5]:-}" ]]; then
        stage5_complete=false
        for model in ss3t msmt; do
            if [[ -f "$dwi_dir/${subject}_model-${model}_tractogram-10M.tck" &&
                  -f "$dwi_dir/${subject}_model-${model}_sift2-weights.txt" ]]; then
                stage5_complete=true
                add_file "$dwi_dir/${subject}_model-${model}_sift2-mu.txt"
                add_file "$dwi_dir/${subject}_model-${model}_sift2-coeffs.txt"
                if [[ "$include_qc" == true ]]; then
                    add_file "$dwi_dir/${subject}_model-${model}_tractogram-200k.tck"
                fi
            fi
        done
        if [[ "$stage5_complete" != true ]]; then
            printf 'Skipping Stage 5 for %s/%s: no complete tractogram/weight pair found.\n' \
                "$subject" "$session" >&2
            ((skipped_count += 1))
        fi
    fi

    # Stage 6: retain mapped annotations, the parcel image used for QC, and
    # connectome/assignment CSVs. The two label-volume conversion inputs can
    # be regenerated from the annotations.
    if [[ -n "${clean_stage[6]:-}" ]]; then
        stage6_complete=false
        for model in ss3t msmt; do
            if [[ -f "$dwi_dir/${subject}_model-${model}_atlas-${atlas_name}_connectome.csv" &&
                  -f "$dwi_dir/${subject}_model-${model}_atlas-${atlas_name}_assignments.csv" ]]; then
                stage6_complete=true
            fi
        done
        if [[ "$stage6_complete" == true ]]; then
            fs_mri_dir="$freesurfer_dir/${subject}_${session}/mri"
            add_file "$fs_mri_dir/${atlas_name}.mgz"
            add_file "$fs_mri_dir/${atlas_name}.nii.gz"
        else
            printf 'Skipping Stage 6 for %s/%s: no complete connectome/assignment pair found.\n' \
                "$subject" "$session" >&2
            ((skipped_count += 1))
        fi
    fi
done

if ((session_count == 0)); then
    echo "No sessions with a dwi directory found under $BIDS_ROOT." >&2
    exit 1
fi

if ((${#targets[@]} == 0)); then
    echo "No eligible intermediate files found under $BIDS_ROOT."
    ((skipped_count == 0)) || printf 'Stage/session checks skipped: %d\n' "$skipped_count"
    exit 0
fi

printf 'BIDS root: %s\n' "$BIDS_ROOT"
printf 'Stages: %s\n' "$stages"
printf 'Include QC-only files: %s\n' "$include_qc"
printf 'Targets matched: %d\n' "${#targets[@]}"
for target in "${targets[@]}"; do
    if [[ "$target" == "$BIDS_ROOT"/* ]]; then
        printf '  %s\n' "${target#"$BIDS_ROOT"/}"
    else
        printf '  %s\n' "$target"
    fi
done
((skipped_count == 0)) || printf 'Stage/session checks skipped: %d\n' "$skipped_count"

if [[ "$dry_run" == true ]]; then
    echo "Dry run: no files were removed."
    exit 0
fi

if [[ "$assume_yes" != true ]]; then
    printf "Type 'delete' to remove these intermediate files: "
    if ! read -r confirmation || [[ "$confirmation" != delete ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

for index in "${!targets[@]}"; do
    rm -f -- "${targets[$index]}"
done
printf 'Removed %d intermediate file(s).\n' "${#targets[@]}"
