#!/bin/bash

# Assuming your files are in a folder named "data"
folder="raw_dicom"

# Iterate over each file in the folder
for file in $folder/*.zip; do
    # Extract the filename without extension
    filename=$(basename "$file" .zip)
    
    # Create a directory for the current file
    mkdir -p "workbench/$filename"
    
    # Execute dcm2bids_helper command
    dcm2bids_helper -d "raw_dicom/$filename.zip" -o "workbench/$filename"
done
