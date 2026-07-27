#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: hcp_recommended_to_bids.sh SOURCE_DIR OUTPUT_DIR

Extract paired HCP Young Adult Recommended archives, retain their complete
contents under sourcedata/hcp, and create a BIDS-Derivatives view of the
preprocessed T1w and diffusion data using hard links.
EOF
}

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 2
fi

source_dir=${1%/}
output_dir=${2%/}
source_data_dir="$output_dir/sourcedata/hcp"

if [[ ! -d "$source_dir" ]]; then
    printf 'Source directory does not exist: %s\n' "$source_dir" >&2
    exit 1
fi

mkdir -p "$output_dir" "$source_data_dir"

mapfile -t diffusion_archives < <(
    find "$source_dir" -maxdepth 1 -type f \
        -name '*_Diffusion3TRecommended.zip' -printf '%f\n' | sort
)

if [[ ${#diffusion_archives[@]} -eq 0 ]]; then
    printf 'No Diffusion3TRecommended archives found in %s\n' "$source_dir" >&2
    exit 1
fi

printf 'participant_id\n' > "$output_dir/participants.tsv"

for diffusion_name in "${diffusion_archives[@]}"; do
    subject=${diffusion_name%%_*}
    structural_name="${subject}_StructuralRecommended.zip"
    diffusion_zip="$source_dir/$diffusion_name"
    structural_zip="$source_dir/$structural_name"

    if [[ ! "$subject" =~ ^[A-Za-z0-9]+$ ]]; then
        printf 'Invalid BIDS subject label derived from %s\n' "$diffusion_name" >&2
        exit 1
    fi
    if [[ ! -f "$structural_zip" ]]; then
        printf 'Missing paired archive: %s\n' "$structural_zip" >&2
        exit 1
    fi
    extracted_subject="$source_data_dir/sub-$subject"
    completion_marker="$extracted_subject/.hcp_bids_complete"
    if [[ -f "$completion_marker" ]]; then
        printf 'Subject %s is already complete; skipping\n' "$subject"
        printf 'sub-%s\n' "$subject" >> "$output_dir/participants.tsv"
        continue
    fi

    archive_subject_dir="$source_data_dir/$subject"
    mkdir -p "$source_data_dir"

    printf 'Extracting subject %s\n' "$subject"
    unzip -oq "$structural_zip" -d "$source_data_dir"
    unzip -oq "$diffusion_zip" -d "$source_data_dir"

    if [[ -e "$extracted_subject" ]]; then
        printf 'Extraction target already exists: %s\n' "$extracted_subject" >&2
        exit 1
    fi
    mv "$archive_subject_dir" "$extracted_subject"

    anat_dir="$output_dir/sub-$subject/anat"
    dwi_dir="$output_dir/sub-$subject/dwi"
    mkdir -p "$anat_dir" "$dwi_dir"

    t1_source="$extracted_subject/T1w/T1w_acpc_dc_restore.nii.gz"
    dwi_source="$extracted_subject/T1w/Diffusion/data.nii.gz"
    bval_source="$extracted_subject/T1w/Diffusion/bvals"
    bvec_source="$extracted_subject/T1w/Diffusion/bvecs"

    for required_file in "$t1_source" "$dwi_source" "$bval_source" "$bvec_source"; do
        if [[ ! -f "$required_file" ]]; then
            printf 'Expected HCP file is missing: %s\n' "$required_file" >&2
            exit 1
        fi
    done

    ln "$t1_source" "$anat_dir/sub-${subject}_desc-preproc_T1w.nii.gz"
    ln "$dwi_source" "$dwi_dir/sub-${subject}_desc-preproc_dwi.nii.gz"
    ln "$bval_source" "$dwi_dir/sub-${subject}_desc-preproc_dwi.bval"
    ln "$bvec_source" "$dwi_dir/sub-${subject}_desc-preproc_dwi.bvec"

    cat > "$anat_dir/sub-${subject}_desc-preproc_T1w.json" <<EOF
{
  "SkullStripped": false,
  "Sources": ["sourcedata/hcp/sub-${subject}/T1w/T1w_acpc_dc_restore.nii.gz"]
}
EOF
    cat > "$dwi_dir/sub-${subject}_desc-preproc_dwi.json" <<EOF
{
  "Sources": ["sourcedata/hcp/sub-${subject}/T1w/Diffusion/data.nii.gz"],
  "SpatialReference": "sub-${subject}/anat/sub-${subject}_desc-preproc_T1w.nii.gz"
}
EOF
    touch "$completion_marker"
    printf 'sub-%s\n' "$subject" >> "$output_dir/participants.tsv"
done

cat > "$output_dir/dataset_description.json" <<'EOF'
{
  "Name": "HCP Young Adult Unrelated - Recommended Preprocessed Data",
  "BIDSVersion": "1.10.1",
  "DatasetType": "derivative",
  "License": "Data use is governed by the HCP Data Use Terms",
  "GeneratedBy": [
    {
      "Name": "HCP minimal preprocessing pipelines",
      "Description": "Recommended structural and diffusion products distributed by the Human Connectome Project"
    },
    {
      "Name": "hcp_recommended_to_bids.sh",
      "Description": "Archive extraction and BIDS-Derivatives organization"
    }
  ]
}
EOF

cat > "$output_dir/README" <<'EOF'
HCP Young Adult Unrelated Recommended preprocessed data

This is a BIDS-Derivatives dataset, not a raw BIDS dataset. The archives contain
outputs from the HCP minimal preprocessing and BEDPOSTX pipelines. Their complete
uncompressed contents are retained under sourcedata/hcp/sub-<label>. The
subject-level anat and dwi files are hard links to selected HCP-preprocessed
images. They occupy no additional payload space. Modifying a linked file changes
the shared data; removing one pathname does not remove the other link.

The DWI series has already undergone HCP preprocessing, including correction and
concatenation. A single raw acquisition PhaseEncodingDirection therefore is not
assigned to the combined derivative.
EOF

printf 'Completed %d subjects in %s\n' "${#diffusion_archives[@]}" "$output_dir"
