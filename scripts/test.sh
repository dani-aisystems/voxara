#!/bin/zsh
# Runs the unit tests. With Command Line Tools only (no Xcode), SwiftPM does not pass the
# Swift Testing macro plugin to the compiler, so point it there explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  swift test "$@"
fi
