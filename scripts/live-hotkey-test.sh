#!/bin/zsh
# Live test of the real path: synthetic key hold → global event tap → microphone → pipeline → overlay → insertion.
# Safe: switches Voxara to test mode, so text can only be inserted into Voxara's own test window.
# Usage: scripts/live-hotkey-test.sh [dictation|prompt] [seconds]
set -uo pipefail
cd "$(dirname "$0")/.."
MODE=${1:-dictation}; SECS=${2:-6}
mkdir -p build/tools
[[ build/tools/vxpost -nt scripts/vxpost.swift ]] || swiftc -O scripts/vxpost.swift -o build/tools/vxpost 2>&1 | grep -v "search path"
[[ build/tools/vxhold -nt scripts/hold.swift ]] || swiftc -O scripts/hold.swift -o build/tools/vxhold 2>&1 | grep -v "search path"
front() { osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'; }

build/tools/vxpost test-mode on; sleep 0.5
build/tools/vxpost open-test-bench; sleep 1.2
osascript -e 'tell application "System Events" to set frontmost of process "Voxara" to true' >/dev/null 2>&1; sleep 0.8
[[ $(front) == com.daniel.voicetext ]] || { echo "ABORT: test bench is not frontmost"; build/tools/vxpost test-mode off; exit 3; }

# Right Option = key 61, device flag 0x40, ⌥ mask 524288; Right Command = key 54, 0x10, mask 1048576
if [[ $MODE == prompt ]]; then ARGS=(54 10 1048576 $SECS); else ARGS=(61 40 524288 $SECS); fi
osascript -e 'tell application "System Events" to set frontmost of process "Voxara" to true' >/dev/null 2>&1
build/tools/vxhold $ARGS &
HOLD=$!
sleep 1.5
echo "during hold: frontmost=$(front)"
echo "voxara windows: $(osascript -e 'tell application "System Events" to tell process "Voxara" to get name of every window' 2>/dev/null)"
wait $HOLD
sleep ${LIVE_WAIT:-8}
echo "after:       frontmost=$(front)"
echo "test bench text: $(osascript -e 'tell application "System Events" to tell process "Voxara" to get value of text area 1 of scroll area 1 of group 1 of window "Voxara Test Bench"' 2>/dev/null)"
build/tools/vxpost test-mode off
/usr/bin/log show --last 30s --info --predicate 'subsystem == "com.daniel.voicetext"' --style compact 2>&1 | grep -E "finished|refused|Pasting|failed" | cut -c1-200 | tail -3
