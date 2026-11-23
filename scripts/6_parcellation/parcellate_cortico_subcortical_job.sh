#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=08:00:00

# Surface cortex -> cortical ribbon -> native T1 merge with registered subcortex.
# Submit with 2_run_parcellate_cortico_subcortical_jobs.sh BIDS_OR_SESSION_DIR.
# MODEL=msmt ATLAS_LABEL_NAME=schaefer100-yeo7 bash this_script.sh SESSION_DIR
set -eo pipefail
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids/sub-ID/ses-ID" >&2
    exit 2
fi
JOB_START_TIME=$SECONDS
report_processing_time() {
    local exit_status=$?
    local elapsed=$((SECONDS - JOB_START_TIME))
    printf "Processing time for %s: %02d:%02d:%02d (HH:MM:SS; exit status: %d)\n" \
        "${fs_subject_id:-$(basename "$0")}" \
        "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))" \
        "$exit_status"

    if [ "$exit_status" -eq 0 ] && [ -n "${WORKFLOW_START_EPOCH:-}" ] && [ -n "${WORKFLOW_TIMING_LOG:-}" ]; then
        local workflow_end_epoch workflow_elapsed workflow_end_timestamp completion_message
        workflow_end_epoch=$(date +%s)
        workflow_elapsed=$((workflow_end_epoch - WORKFLOW_START_EPOCH))
        workflow_end_timestamp=$(date '+%Y-%m-%d %H:%M:%S %z')
        printf -v completion_message \
            'Cortico-subcortical parcellation completed successfully for %s: %s; elapsed since workflow start: %02d:%02d:%02d (HH:MM:SS)' \
            "${fs_subject_id:-$(basename "$0")}" "$workflow_end_timestamp" \
            "$((workflow_elapsed / 3600))" "$(((workflow_elapsed % 3600) / 60))" \
            "$((workflow_elapsed % 60))"
        printf '%s\n' "$completion_message" | tee -a "$WORKFLOW_TIMING_LOG"
    fi
}
trap report_processing_time EXIT

ml FreeSurfer/6.0.0
ml MRtrix
export NO_FSFAST=1
# Legacy FreeSurfer setup contains optional grep probes that return 1.
set +e
set +o pipefail
source "$FREESURFER_HOME/SetUpFreeSurfer.sh"
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${PIPELINE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
export SUBJECTS_DIR="${FREESURFER_SUBJECTS_DIR:-$PIPELINE_ROOT/freesurfer}"
MODEL="${MODEL:-msmt}"
case "$MODEL" in msmt|ss3t) ;; *) echo "MODEL must be msmt or ss3t" >&2; exit 2 ;; esac
NTHREADS="${NTHREADS:-${SLURM_CPUS_PER_TASK:-4}}"
ATLAS_LABEL_NAME="${ATLAS_LABEL_NAME:-schaefer100-yeo7}"
ATLAS_ROOT="${ATLAS_ROOT:-$PIPELINE_ROOT/templates_parcellations}"
ATLAS_DIR="${ATLAS_DIR:-$ATLAS_ROOT/$ATLAS_LABEL_NAME}"
TABLE_LABEL_NAME="${TABLE_LABEL_NAME:-LUT_${ATLAS_LABEL_NAME}}"
SUBCORTICAL_LABEL_NAME="${SUBCORTICAL_LABEL_NAME:-tians2}"
SUBCORTICAL_LUT="${SUBCORTICAL_LUT:-$ATLAS_ROOT/$SUBCORTICAL_LABEL_NAME/lut/LUT_${SUBCORTICAL_LABEL_NAME}.txt}"

session_dir="$(readlink -f "$1")"
subject_id="$(basename "$(dirname "$session_dir")")"
fs_subject_id="${subject_id}_$(basename "$session_dir")"
fs_subject_dir="$SUBJECTS_DIR/$fs_subject_id"
dwi_dir="$session_dir/dwi"
t1_native="$session_dir/anat/${subject_id}_T1w.nii.gz"
tracks="$dwi_dir/${subject_id}_model-${MODEL}_tractogram-10M.tck"
weights="$dwi_dir/${subject_id}_model-${MODEL}_sift2-weights.txt"
combined_atlas="${ATLAS_LABEL_NAME}-${SUBCORTICAL_LABEL_NAME}"
work_dir="$dwi_dir/parcellation/$combined_atlas"
output_prefix="$dwi_dir/${subject_id}_atlas-${combined_atlas}"
connectome_prefix="$dwi_dir/${subject_id}_model-${MODEL}_atlas-${combined_atlas}"

# Accept the original flat folders and downloaded fsaverage bundles.
lh_annot="$ATLAS_DIR/lh.${ATLAS_LABEL_NAME}.annot"
rh_annot="$ATLAS_DIR/rh.${ATLAS_LABEL_NAME}.annot"
if [ ! -s "$lh_annot" ] || [ ! -s "$rh_annot" ]; then
    shopt -s nullglob
    lh_annotations=("$ATLAS_DIR"/surface/fsaverage/lh.*.annot)
    rh_annotations=("$ATLAS_DIR"/surface/fsaverage/rh.*.annot)
    shopt -u nullglob
    if [ "${#lh_annotations[@]}" -ne 1 ] || [ "${#rh_annotations[@]}" -ne 1 ]; then
        echo "Expected one fsaverage annotation per hemisphere in $ATLAS_DIR" >&2
        exit 1
    fi
    lh_annot="${lh_annotations[0]}"
    rh_annot="${rh_annotations[0]}"
fi
lut_dir="$ATLAS_DIR"
[ -s "$lut_dir/$TABLE_LABEL_NAME.txt" ] || lut_dir="$ATLAS_DIR/lut"
for input in "$lh_annot" "$rh_annot" "$lut_dir/$TABLE_LABEL_NAME.txt" \
    "$lut_dir/${TABLE_LABEL_NAME}_OUTPUT.txt" "$SUBCORTICAL_LUT" "$t1_native" \
    "$tracks" "$weights" "$dwi_dir/rigid_T1toDWI.txt" \
    "$fs_subject_dir/mri/brain.mgz" "$fs_subject_dir/mri/ribbon.mgz"; do
    if [ ! -s "$input" ]; then
        echo "Missing input: $input" >&2
        exit 1
    fi
done
if [ ! -d "$SUBJECTS_DIR/fsaverage" ]; then
    echo "Set up $SUBJECTS_DIR/fsaverage using $FREESURFER_HOME/subjects/fsaverage" >&2
    exit 1
fi
mkdir -p "$work_dir"
echo "Subject: $fs_subject_id; cortex: $ATLAS_LABEL_NAME; subcortex: $SUBCORTICAL_LABEL_NAME; model: $MODEL"

# Match cortical IDs by LUT names, independently of the atlas naming scheme.
# FreeSurfer custom annotations use 1000+index (lh), 2000+index (rh).
# The OUTPUT table defines ordering; inherited aseg and unknown IDs are excluded.
awk 'FNR == NR {
    if ($1 ~ /^[0-9]+$/ && (($1 > 1000 && $1 < 2000) || ($1 > 2000 && $1 < 3000))) source[$2]=$1
    next
}
$1 ~ /^[0-9]+$/ && $1 > 0 {
    if (!($2 in source)) {print "Unmatched cortical LUT name: " $2 > "/dev/stderr"; exit 1}
    print $1, source[$2], $2, (NF >= 6 ? $3 : 128), (NF >= 6 ? $4 : 128), (NF >= 6 ? $5 : 128), (NF >= 6 ? $6 : 0)
}' "$lut_dir/$TABLE_LABEL_NAME.txt" "$lut_dir/${TABLE_LABEL_NAME}_OUTPUT.txt" \
    | sort -n -k1,1 > "$work_dir/cortex_mapping.txt"
awk 'BEGIN {OFS="\t"} {print $2,$3,$4,$5,$6,$7}' "$work_dir/cortex_mapping.txt" > "$work_dir/cortex_input_lut.txt"
awk 'BEGIN {OFS="\t"} {print NR,$3,$4,$5,$6,$7}' "$work_dir/cortex_mapping.txt" > "$work_dir/cortex_output_lut.txt"
n_cortex="$(wc -l < "$work_dir/cortex_mapping.txt")"

# Normalize two-column or FreeSurfer-style subcortical LUTs. Always define IDs
# from the complete atlas, so a missing subject parcel never shifts numbering.
awk '$1 ~ /^[0-9]+$/ && $1 > 0 {
    print $1,$2,(NF >= 6 ? $3 : 128),(NF >= 6 ? $4 : 128),(NF >= 6 ? $5 : 128),(NF >= 6 ? $6 : 0)
}' "$SUBCORTICAL_LUT" | sort -n -k1,1 > "$work_dir/subcortex_input_lut.txt"
for table in "$work_dir/cortex_input_lut.txt" "$work_dir/cortex_output_lut.txt" "$work_dir/subcortex_input_lut.txt"; do
    awk 'seen_id[$1]++ || seen_name[$2]++ {bad=1} END {if (!NR || bad) exit 1}' "$table" || {
        echo "Empty or duplicate IDs/names in $table" >&2; exit 1;
    }
done
awk -v offset="$n_cortex" 'BEGIN {OFS="\t"} {print offset+NR,$2,$3,$4,$5,$6}' \
    "$work_dir/subcortex_input_lut.txt" > "$work_dir/subcortex_output_lut.txt"
cat "$work_dir/cortex_output_lut.txt" "$work_dir/subcortex_output_lut.txt" > "${output_prefix}_lut.txt"
awk -v cortex="$ATLAS_LABEL_NAME" -v subcortex="$SUBCORTICAL_LABEL_NAME" -v offset="$n_cortex" '
    BEGIN {OFS="\t"; print "index","name","tissue","source","source_index"}
    FNR == NR {print FNR,$2,"cortex",cortex,$1; next}
    {print offset+FNR,$2,"subcortex",subcortex,$1}
' "$work_dir/cortex_input_lut.txt" "$work_dir/subcortex_input_lut.txt" > "${output_prefix}_nodes.tsv"

# Supply SUBCORTICAL_NATIVE to reuse any previously registered subcortical atlas.
# Otherwise the first cortical run creates the shared native map; later atlases
# reuse it. Selecting a different subcortical atlas creates a different map.
if [ -z "${SUBCORTICAL_NATIVE:-}" ]; then
    SUBCORTICAL_NATIVE="$session_dir/anat/${subject_id}_atlas-${SUBCORTICAL_LABEL_NAME}_space-T1w_labels.nii.gz"
    if [ ! -s "$SUBCORTICAL_NATIVE" ]; then
        PIPELINE_ROOT="$PIPELINE_ROOT" ATLAS_ROOT="$ATLAS_ROOT" \
        FREESURFER_SUBJECTS_DIR="$SUBJECTS_DIR" SUBCORTICAL_LABEL_NAME="$SUBCORTICAL_LABEL_NAME" \
        NTHREADS="$NTHREADS" bash "$PIPELINE_ROOT/scripts/6_parcellation/register_subcortical_job.sh" "$session_dir"
    fi
fi
if [ ! -s "$SUBCORTICAL_NATIVE" ]; then
    echo "Missing registered subcortical atlas: $SUBCORTICAL_NATIVE" >&2
    exit 1
fi
echo "Using registered subcortex: $SUBCORTICAL_NATIVE"
printf 'cortex\t%s\nsubcortex\t%s\nregistered_subcortex\t%s\nmodel\t%s\nn_cortex\t%s\n' \
    "$ATLAS_LABEL_NAME" "$SUBCORTICAL_LABEL_NAME" "$SUBCORTICAL_NATIVE" "$MODEL" "$n_cortex" \
    > "$work_dir/inputs.tsv"

# Transfer labels along the registered surfaces, then fill only the cortical
# ribbon. Do not replace the subject's cortical boundaries with an MNI volume.
for hemi in lh rh; do
    source_annot="$lh_annot"
    [ "$hemi" = lh ] || source_annot="$rh_annot"
    mri_surf2surf --srcsubject fsaverage --trgsubject "$fs_subject_id" --hemi "$hemi" \
        --sval-annot "$source_annot" --tval "$fs_subject_dir/label/${hemi}.${ATLAS_LABEL_NAME}.annot"
done
mri_aparc2aseg --s "$fs_subject_id" --annot "$ATLAS_LABEL_NAME" --ribbon \
    --o "$work_dir/cortex_aparc+aseg.mgz"
labelconvert "$work_dir/cortex_aparc+aseg.mgz" "$work_dir/cortex_input_lut.txt" \
    "$work_dir/cortex_output_lut.txt" "$work_dir/cortex_space-fsnative.nii.gz" -force
mrtransform "$work_dir/cortex_space-fsnative.nii.gz" "$work_dir/cortex_space-T1w.nii.gz" \
    -template "$t1_native" -interp nearest -datatype uint32 -force

# A supplied native map must already be in this T1's scanner coordinates.
# This changes its grid only; it cannot fix a map from another subject/space.
mrtransform "$SUBCORTICAL_NATIVE" "$work_dir/subcortex_space-T1w_labels.nii.gz" \
    -template "$t1_native" -interp nearest -force
labelconvert "$work_dir/subcortex_space-T1w_labels.nii.gz" "$work_dir/subcortex_input_lut.txt" \
    "$work_dir/subcortex_output_lut.txt" "$work_dir/subcortex_space-T1w_nodes.nii.gz" -force

# Cortex wins where atlases overlap. Retain separate maps so these overlaps and
# any subcortical parcel loss can be inspected instead of silently dilating labels.
mrcalc "$work_dir/cortex_space-T1w.nii.gz" 0 -gt "$work_dir/cortex_space-T1w.nii.gz" \
    "$work_dir/subcortex_space-T1w_nodes.nii.gz" -if \
    "${output_prefix}_space-T1w_parcels.nii.gz" -datatype uint32 -force

# Move the high-resolution anatomical grid into DWI coordinates without
# resampling onto coarse b0 voxels, preserving thin cortex and small nuclei.
mrtransform "${output_prefix}_space-T1w_parcels.nii.gz" "${output_prefix}_space-dwi_parcels.nii.gz" \
    -linear "$dwi_dir/rigid_T1toDWI.txt" -datatype uint32 -force
tck2connectome "$tracks" "${output_prefix}_space-dwi_parcels.nii.gz" "${connectome_prefix}_connectome.csv" \
    -tck_weights_in "$weights" -out_assignments "${connectome_prefix}_assignments.csv" \
    -assignment_radial_search 4 -symmetric -zero_diagonal -nthreads "$NTHREADS" -force

echo "Combined atlas: ${output_prefix}_space-dwi_parcels.nii.gz"
