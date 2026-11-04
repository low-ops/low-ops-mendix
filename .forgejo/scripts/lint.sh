#!/usr/bin/env bash
set -eu

root="$(cd "$(dirname "$0")" && pwd)"

cp -r /app/rules .
mxlint export-model

set +e
mxlint lint --json-file=report.json
mxlint_status=$?
set -e

bash "$root/stage_to_share.sh" report.json report.json

report_status=0
python "$root/report_failures.py" report.json "Lint report" || report_status=$?

if [ "$mxlint_status" -ne 0 ] || [ "$report_status" -ne 0 ]; then
  exit 1
fi
