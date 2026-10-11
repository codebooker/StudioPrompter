#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../.build
node ../desktop/test/android-fixture.cjs > ../.build/android-port.json 2> ../.build/android-fixture.log </dev/null &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
for attempt in $(seq 1 30); do
  if test -s ../.build/android-port.json; then break; fi
  if ! kill -0 "$fixture_pid" 2>/dev/null; then cat ../.build/android-fixture.log; exit 1; fi
  sleep 0.2
 done
port=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("../.build/android-port.json", "utf8")).port)')
gradle --no-daemon connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.studioPort="$port"
