#!/bin/sh
# Carry a challenge link from one simulator to another, for testing the
# head-to-head without universal links (docs/ROADMAP.md → Head-to-head).
#
#   1. On the sender's simulator, finish a run, tap Share → Copy.
#   2. scripts/sim-challenge.sh [--launch] <sender> <receiver>
#
# By default the link opens the way a tap would, and iOS asks "Open in
# Unspool?" on the receiver. `--launch` relaunches the receiver's app with the
# link instead (`-uiOpenLink`), with no prompt — for scripted runs.
#
# Simulators are names or UDIDs (`xcrun simctl list devices booted`). It reads
# the sender's pasteboard, finds the `unspool-debug://` link in the share text,
# and opens it on the receiver. A reply goes back the same way, swapped.
# Debug builds only: Release registers no `unspool-debug` scheme.
set -eu
launch=false
if [ "${1:-}" = "--launch" ]; then launch=true; shift; fi
if [ $# -ne 2 ]; then
    echo "usage: $0 [--launch] <sender-simulator> <receiver-simulator>" >&2
    exit 64
fi
link=$(xcrun simctl pbpaste "$1" | grep -o 'unspool-debug://[^[:space:]]*' | head -n 1 || true)
if [ -z "$link" ]; then
    echo "No unspool-debug:// link on $1's pasteboard. Share → Copy on it first." >&2
    exit 1
fi
if $launch; then
    xcrun simctl launch --terminate-running-process "$2" abe.movie-quiz -uiOpenLink "$link" >/dev/null
else
    xcrun simctl openurl "$2" "$link"
fi
echo "Opened on $2: $link"
