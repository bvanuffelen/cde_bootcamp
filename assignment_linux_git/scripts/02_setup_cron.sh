#!/bin/bash
#
# 02_setup_cron.sh
#
# Purpose : Schedules 01_etl_script.sh to run automatically every day at 12:00 AM
#           using cron.
#
# Usage   : ./02_setup_cron.sh
#
# Notes   : Cron is the standard Linux job scheduler. A cron schedule has
#           5 fields:  minute  hour  day-of-month  month  day-of-week
#           "0 0 * * *" means: minute 0, hour 0 (midnight), every day of
#           every month, every day of the week -> i.e. "every day at 00:00".
# ---------------------------------------------------------------------------

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ETL_SCRIPT="${BASE_DIR}/scripts/01_etl_script.sh"
LOG_FILE="${BASE_DIR}/logs/cron_etl.log"

# Make sure the ETL script is executable.
chmod +x "${ETL_SCRIPT}"
mkdir -p "${BASE_DIR}/logs"

# The line we want in the crontab:
#   - Runs at 00:00 every day
#   - Redirects stdout and stderr to a log file so we can check the output
#     of runs that happen while nobody is watching the terminal.
CRON_JOB="0 0 * * * ${ETL_SCRIPT} >> ${LOG_FILE} 2>&1"

echo "Preparing to install the following cron job:"
echo "  ${CRON_JOB}"
echo ""

# Grab the current crontab (if any). "|| true" prevents the script exiting
# via set -e when the user has no existing crontab (crontab -l errors out).
EXISTING_CRON="$(crontab -l 2>/dev/null || true)"

# Only add the job if it isn't already present, to avoid duplicate entries
# if this script is run more than once.
if echo "${EXISTING_CRON}" | grep -Fq "${ETL_SCRIPT}"; then
    echo "A cron job for etl_script.sh already exists. No changes made."
else
    # Combine the existing crontab with the new job and load it back in.
    { echo "${EXISTING_CRON}"; echo "${CRON_JOB}"; } | crontab -
    echo "Cron job installed successfully."
fi

echo ""
echo "Current crontab:"
crontab -l
