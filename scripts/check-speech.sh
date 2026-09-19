#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
say -v Samantha -r 190 -f Tests/Fixtures/reading.txt -o .build/reading.aiff
# A fresh cache tests the same explicit-download path used by a new installation.
CACHE="$PWD/.build/download-check-$(date +%s)-$$"
swift run -c release WhisperCheck --download-check "$CACHE" "$PWD/.build/reading.aiff"
swift run -c release WhisperCheck --stream "$PWD/.build/reading.aiff" "$PWD/Tests/Fixtures/reading.txt"
echo "PASS: first download, cached reopen, and quiet streaming speech recognition"
