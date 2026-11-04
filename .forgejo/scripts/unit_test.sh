#!/usr/bin/env bash
set -eu

caller="/srv/shared/${CORRELATION}/ci/mx_app_unit_test_caller.py"
if [ ! -f "$caller" ]; then
  echo "Unit test caller script was not staged during build" >&2
  exit 1
fi

cp "$caller" /opt/mendix/build/mx-app-unit-test-caller.py

cd /opt/mendix/build
./startup.py &

set +e
python ./mx-app-unit-test-caller.py \
  --api-password "$MX_UnitTesting_RemoteApiPassword" \
  --json-file /tmp/results.json
status=$?
set -e

bash "$root/stage_to_share.sh" /tmp/results.json results.json
exit "$status"
