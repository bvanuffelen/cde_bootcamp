#!/bin/bash
#
# 01_etl_script.sh
#
# Purpose : Simple ETL (Extract, Transform, Load) pipeline for CoreDataEngineers.
#           Downloads the Stats NZ Annual Enterprise Survey CSV, transforms it,
#           and loads the result into a "Gold" directory.
#
# Usage   : ./01_etl_script.sh
# ---------------------------------------------------------------------------

# Exit immediately if a command fails, treat unset variables as errors,
# and fail a pipeline if any command within it fails.
set -euo pipefail

# ----------------------------- CONFIGURATION --------------------------------

# The source URL is stored as an environment variable so it is not hard-coded
# inside the script. This makes the script reusable if the source changes.
export CSV_URL="https://www.stats.govt.nz/assets/Uploads/Annual-enterprise-survey/Annual-enterprise-survey-2023-financial-year-provisional/Download-data/annual-enterprise-survey-2023-financial-year-provisional.csv"

# Base directory = the directory this script lives in, so it can be run
# from anywhere (e.g. cron) and still find the right folders.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RAW_DIR="${BASE_DIR}/raw"
TRANSFORMED_DIR="${BASE_DIR}/Transformed"
GOLD_DIR="${BASE_DIR}/Gold"
LOG_DIR="${BASE_DIR}/logs"

RAW_FILE="${RAW_DIR}/annual-enterprise-survey-2023-financial-year-provisional.csv"
TRANSFORMED_FILE="${TRANSFORMED_DIR}/2023_year_finance.csv"
GOLD_FILE="${GOLD_DIR}/2023_year_finance.csv"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# Make sure all required folders exist before we start.
mkdir -p "${RAW_DIR}" "${TRANSFORMED_DIR}" "${GOLD_DIR}" "${LOG_DIR}"

echo "===================================================================="
echo " CoreDataEngineers ETL Pipeline - Run started: ${TIMESTAMP}"
echo "===================================================================="

# ------------------------------- EXTRACT ------------------------------------

echo ""
echo "[EXTRACT] Downloading CSV from source URL..."
echo "[EXTRACT] URL: ${CSV_URL}"

# -s  : silent mode (no progress meter)
# -S  : show errors even in silent mode
# -L  : follow redirects
# -o  : write to the given output file
curl -sSL -o "${RAW_FILE}" "${CSV_URL}"

# Confirm that the file was actually saved in the raw folder.
if [[ -f "${RAW_FILE}" ]]; then
    FILE_SIZE=$(du -h "${RAW_FILE}" | cut -f1)
    echo "[EXTRACT] SUCCESS: File saved to ${RAW_FILE} (size: ${FILE_SIZE})"
else
    echo "[EXTRACT] ERROR: File was not saved to ${RAW_DIR}. Aborting."
    exit 1
fi

# ------------------------------- TRANSFORM ----------------------------------

echo ""
echo "[TRANSFORM] Renaming column 'Variable_code' -> 'variable_code' and"
echo "[TRANSFORM] selecting columns: Year, Value, Units, variable_code..."

# We use awk to:
#   1. Read the header row and rename "Variable_code" to "variable_code".
#   2. Work out the column positions of year, Value, Units, variable_code
#      dynamically (so the script isn't hard-coded to fixed column numbers).
#   3. Print only those four columns, in that order, for every row.
awk -F',' '
    BEGIN { OFS="," }
    NR == 1 {
        # Rename the header on the fly
        for (i = 1; i <= NF; i++) {
            col = $i
            if (col == "Variable_code") { col = "variable_code" }
            header[i] = col
            # Map column name -> column index for later lookups
            idx[col] = i
        }
        # Print the new, reduced header
        print header[idx["Year"]], header[idx["Value"]], header[idx["Units"]], header[idx["variable_code"]]
        next
    }
    {
        print $(idx["Year"]), $(idx["Value"]), $(idx["Units"]), $(idx["variable_code"])
    }
' "${RAW_FILE}" > "${TRANSFORMED_FILE}"

# Confirm the transformed file was created in the Transformed folder.
if [[ -f "${TRANSFORMED_FILE}" ]]; then
    ROW_COUNT=$(wc -l < "${TRANSFORMED_FILE}")
    echo "[TRANSFORM] SUCCESS: File saved to ${TRANSFORMED_FILE} (${ROW_COUNT} lines, including header)"
else
    echo "[TRANSFORM] ERROR: Transformed file was not created. Aborting."
    exit 1
fi

# --------------------------------- LOAD -------------------------------------

echo ""
echo "[LOAD] Loading transformed data into the Gold folder..."

cp "${TRANSFORMED_FILE}" "${GOLD_FILE}"

# Confirm the file has been saved into the Gold folder.
if [[ -f "${GOLD_FILE}" ]]; then
    echo "[LOAD] SUCCESS: File saved to ${GOLD_FILE}"
else
    echo "[LOAD] ERROR: File was not saved to ${GOLD_DIR}. Aborting."
    exit 1
fi

# ------------------------------- SUMMARY ------------------------------------

echo ""
echo "===================================================================="
echo " ETL Pipeline completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
echo "   Raw file:         ${RAW_FILE}"
echo "   Transformed file: ${TRANSFORMED_FILE}"
echo "   Gold file:        ${GOLD_FILE}"
echo "====================================================================" | tee -a "${LOG_DIR}/etl_run.log"
