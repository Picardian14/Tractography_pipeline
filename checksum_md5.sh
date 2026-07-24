#!/bin/bash

# Iterate over all files in input path that have .md5 extension and compute their MD5 checksums
DIR="$1"
if [ -z "$DIR" ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi
cd "$DIR" || { echo "Directory $DIR does not exist."; exit 1; }
for file in "$DIR"/*.md5; do
    if [ -f "$file" ]; then
        md5sum -c "$file"         
    fi
done
#certutil -hashfile "$file" MD5 | awk 'NR==2 {print $file}'