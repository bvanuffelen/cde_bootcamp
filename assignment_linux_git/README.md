# Linux and Git Project — CoreDataEngineers

A Bash-based ETL pipeline, cron scheduling, and file-organization tooling
built as part of the CoreDataEngineers Data Engineer onboarding project.

## Project Structure

```
.
├── scripts/
│   ├── 01_etl_script.sh       # Extract, Transform, Load pipeline
│   ├── 02_setup_cron.sh       # Installs the daily cron job for 01_etl_script.sh
│   └── 03_move_csv_json.sh    # Moves CSV/JSON files into json_and_CSV/
├── raw/                    # Downloaded (extracted) CSV lands here
├── Transformed/            # Transformed CSV lands here
├── Gold/                   # Final loaded CSV lands here
├── json_and_CSV/           # Destination for move_csv_json.sh
├── sample_data/            # Example CSV/JSON files for testing move_csv_json.sh
└── logs/                   # ETL and cron run logs (created at runtime)
```

## 1. ETL Pipeline (`scripts/01_etl_script.sh`)

Downloads the [Stats NZ Annual Enterprise Survey 2023 (provisional)](https://www.stats.govt.nz/assets/Uploads/Annual-enterprise-survey/Annual-enterprise-survey-2023-financial-year-provisional/Download-data/annual-enterprise-survey-2023-financial-year-provisional.csv)
CSV and runs it through three stages:

- **Extract** — Downloads the CSV via `curl` and saves it to `raw/`. The
  script confirms the file exists before continuing.
- **Transform** — Renames the `Variable_code` column to `variable_code`,
  then selects only `year, Value, Units, variable_code`, saving the result
  as `Transformed/2023_year_finance.csv`.
- **Load** — Copies the transformed file into `Gold/2023_year_finance.csv`
  and confirms it was saved.

The source URL is defined as an environment variable (`CSV_URL`) inside the
script rather than hard-coded into the `curl` command, and every stage
prints a status message so the run can be monitored or debugged from logs.

**Run it:**
```bash
chmod +x scripts/01_etl_script.sh
./scripts/01_etl_script.sh
```

## 2. Scheduling with Cron (`scripts/02_setup_cron.sh`)

[Cron](https://en.wikipedia.org/wiki/Cron) is the standard Linux job
scheduler daemon. A crontab entry has five time fields followed by the
command to run:

```
minute hour day-of-month month day-of-week   command
  0     0        *          *       *        /path/to/01_etl_script.sh
```

`0 0 * * *` means "run at minute 0 of hour 0" — i.e. every day at
midnight (12:00 AM).

`02_setup_cron.sh` installs this entry into the current user's crontab
(without wiping out any existing cron jobs) and redirects output to
`logs/cron_etl.log`.

**Run it:**
```bash
chmod +x scripts/02_setup_cron.sh
./scripts/02_setup_cron.sh
```

**Verify it was installed:**
```bash
crontab -l
```

## 3. Moving CSV/JSON Files (`scripts/03_move_csv_json.sh`)

Moves every `.csv` and `.json` file (case-insensitive) from a source folder
into a destination folder called `json_and_CSV` (created automatically if
it doesn't exist). Works with zero, one, or many matching files, and
leaves any other file types untouched.

**Usage:**
```bash
./scripts/03_move_csv_json.sh <source_folder> [destination_folder]
```

**Example** (using the sample data included in this repo):
```bash
chmod +x scripts/03_move_csv_json.sh
./scripts/03_move_csv_json.sh ./sample_data ./json_and_CSV
```

## Requirements

- Bash 4+
- `curl`
- `cron` (for scheduling)
- Standard GNU coreutils (`awk`, `mv`, `du`, `wc`)
