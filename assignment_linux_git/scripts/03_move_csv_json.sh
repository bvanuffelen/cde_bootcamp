#!/bin/bash
#
# 03_move_csv_json.sh
#
# Purpose : Moves all .csv and .json files from a source folder into a
#           destination folder named "json_and_CSV". Works with any number
#           of CSV/JSON files (zero, one, or many).
#
# Usage   : ./03_move_csv_json.sh <source_folder> [destination_folder]
#           If destination_folder is omitted, it defaults to "json_and_CSV"
#           in the current directory.
#
# Example : ./03_move_csv_json.sh ./sample_data
#           ./03_move_csv_json.sh ./sample_data /home/user/archive/json_and_CSV
# ---------------------------------------------------------------------------

set -euo pipefail

# ----------------------------- ARGUMENT CHECK -------------------------------

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <source_folder> [destination_folder]"
    exit 1
fi

SOURCE_DIR="$1"
DEST_DIR="${2:-./json_and_CSV}"

if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "ERROR: Source folder '${SOURCE_DIR}' does not exist."
    exit 1
fi

# Create the destination folder if it doesn't already exist.
mkdir -p "${DEST_DIR}"

echo "===================================================================="
echo " Moving CSV and JSON files"
echo "   Source:      ${SOURCE_DIR}"
echo "   Destination: ${DEST_DIR}"
echo "===================================================================="

# ------------------------------- MOVE FILES ---------------------------------

# Enable nullglob so that a pattern that matches nothing expands to nothing
# (rather than the literal pattern string), which lets us safely handle the
# case of zero matching files.
shopt -s nullglob nocaseglob

# Collect all .csv and .json files (case-insensitive) in the source folder.
files=("${SOURCE_DIR}"/*.csv "${SOURCE_DIR}"/*.json)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No CSV or JSON files found in '${SOURCE_DIR}'. Nothing to move."
else
    moved_count=0
    for file in "${files[@]}"; do
        mv -v "${file}" "${DEST_DIR}/"
        # Note: use arithmetic assignment (not ((moved_count++))) because
        # under `set -e`, ((x++)) returns a false exit status when x starts
        # at 0, which would abort the script after the very first file.
        moved_count=$((moved_count + 1))
    done
    echo "--------------------------------------------------------------------"
    echo "SUCCESS: Moved ${moved_count} file(s) to '${DEST_DIR}'."
fi

# Restore default glob behaviour.
shopt -u nullglob nocaseglob
