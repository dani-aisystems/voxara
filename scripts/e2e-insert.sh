#!/bin/zsh
# End-to-end insertion test. Safe by construction:
#   * every target is a throwaway window this script opens itself,
#   * the script verifies the frontmost app before posting anything,
#   * Voxara itself refuses to insert unless the expected bundle ID is frontmost,
#   * the clipboard is checked to be restored afterwards.
# Usage: scripts/e2e-insert.sh <testbench|textedit|terminal|brave|safari> [clip] [dictation|prompt]
set -uo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:?target: testbench|textedit|terminal|brave|safari}
CLIP=${2:-en-redesign}
MODE=${3:-dictation}
AUDIO="$PWD/bench/audio/$CLIP.wav"
[[ -f $AUDIO ]] || { echo "missing $AUDIO (run scripts/make-test-audio.sh)"; exit 2; }

mkdir -p build/tools
for tool in vxpost; do
  [[ build/tools/$tool -nt scripts/$tool.swift ]] || swiftc -O scripts/$tool.swift -o build/tools/$tool 2>&1 | grep -v "search path"
done
POST=build/tools/vxpost

# Waits until the focused UI element of a process has the given accessibility role (so the target can accept text).
wait_focus() {
  local proc=$1 role=$2
  for _ in {1..20}; do
    [[ $(osascript -e "tell application \"System Events\" to tell process \"$proc\" to get value of attribute \"AXRole\" of (value of attribute \"AXFocusedUIElement\")" 2>/dev/null) == $role ]] && return 0
    sleep 0.25
  done
  return 1
}

front() { osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'; }
pgrep -x Voxara >/dev/null || { echo "Voxara is not running"; exit 2; }
[[ $(defaults read com.daniel.voicetext EnableDebugCommands 2>/dev/null) == 1 ]] || { echo "Enable debug commands first (see docs/testing.md)"; exit 2; }

SENTINEL="CLIPBOARD-SENTINEL-$RANDOM"
BEFORE_APP=$(front)
cleanup() { :; }

case $TARGET in
  testbench)
    BUNDLE=com.daniel.voicetext
    $POST open-test-bench; sleep 1.2
    osascript -e 'tell application "System Events" to set frontmost of process "Voxara" to true' >/dev/null 2>&1; sleep 0.8
    read_text() { osascript -e 'tell application "System Events" to tell process "Voxara" to get value of (text area 1 of scroll area 1 of group 1 of window "Voxara Test Bench")' 2>/dev/null; }
    cleanup() { osascript -e 'tell application "System Events" to tell process "Voxara" to perform action "AXPress" of (first button of window "Voxara Test Bench" whose title is "Clear")' 2>/dev/null; }
    ;;
  textedit)
    BUNDLE=com.apple.TextEdit
    osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' -e 'delay 0.5' >/dev/null
    wait_focus TextEdit AXTextArea || { echo "ABORT: TextEdit text area never got focus"; cleanup; exit 3; }
    read_text() { osascript -e 'tell application "TextEdit" to get text of document 1'; }
    cleanup() { osascript -e 'tell application "TextEdit" to close document 1 saving no' 2>/dev/null; }
    ;;
  terminal)
    BUNDLE=com.apple.Terminal
    rm -f /tmp/voxara-e2e.txt
    osascript -e 'tell application "Terminal" to activate' -e 'tell application "Terminal" to do script "cat > /tmp/voxara-e2e.txt"' -e 'delay 1.2' >/dev/null
    wait_focus Terminal AXTextArea || { echo "ABORT: Terminal never got focus"; cleanup; exit 3; }
    read_text() {
      osascript -e 'tell application "System Events" to keystroke return' -e 'delay 0.3' -e 'tell application "System Events" to keystroke "d" using control down' >/dev/null 2>&1
      sleep 0.6; cat /tmp/voxara-e2e.txt 2>/dev/null
    }
    cleanup() { osascript -e 'tell application "Terminal" to close front window saving no' 2>/dev/null; rm -f /tmp/voxara-e2e.txt; }
    ;;
  brave|safari)
    [[ $TARGET == brave ]] && { APP="Brave Browser"; BUNDLE=com.brave.Browser; } || { APP="Safari"; BUNDLE=com.apple.Safari; }
    PAGE=/tmp/voxara-e2e-page.html
    # The page mirrors its textarea into the tab title, which AppleScript can read without any browser permission.
    echo '<!doctype html><title>VX-E2E:</title><textarea id=t autofocus rows=8 cols=60 oninput="document.title=&quot;VX-E2E:&quot;+this.value"></textarea>' > $PAGE
    # Open the page in a brand-new window of its own; never touch the user's existing tabs.
    if [[ $TARGET == brave ]]; then
      osascript -e 'tell application "Brave Browser" to activate' \
                -e 'tell application "Brave Browser" to make new window' \
                -e 'tell application "Brave Browser" to set URL of active tab of front window to "file:///tmp/voxara-e2e-page.html"' >/dev/null 2>&1
      tab_title() { osascript -e 'tell application "Brave Browser" to get title of active tab of front window' 2>/dev/null; }
      cleanup() { osascript -e 'tell application "Brave Browser" to if (title of active tab of front window) starts with "VX-E2E" then close front window' 2>/dev/null; rm -f $PAGE; }
    else
      osascript -e 'tell application "Safari" to activate' \
                -e 'tell application "Safari" to make new document with properties {URL:"data:text/html;charset=utf-8,%3Ctitle%3EVX-E2E%3A%3C%2Ftitle%3E%3Ctextarea%20autofocus%20rows%3D8%20cols%3D60%20oninput%3D%22document.title%3D%27VX-E2E%3A%27%2Bthis.value%22%3E%3C%2Ftextarea%3E"}' >/dev/null 2>&1
      tab_title() { osascript -e 'tell application "Safari" to get name of current tab of front window' 2>/dev/null; }
      cleanup() { osascript -e 'tell application "Safari" to if (name of current tab of front window) starts with "VX-E2E" then close front window' 2>/dev/null; rm -f $PAGE; }
    fi
    for _ in {1..16}; do [[ $(tab_title) == VX-E2E* ]] && break; sleep 0.5; done
    # Hard gate: the active tab must be our marker page, otherwise we could paste into one of the user's tabs.
    [[ $(tab_title) == VX-E2E* ]] || { echo "ABORT: active tab is '$(tab_title)', not the test page. Nothing was inserted."; cleanup; exit 3; }
    # autofocus on the page puts the caret in the textarea; clicking would move focus away from it.
    sleep 0.5
    read_text() { tab_title | sed 's/^VX-E2E://'; }
    ;;
  *) echo "unknown target"; exit 2 ;;
esac

# Safety gate: the target must really be frontmost before we ask Voxara to insert anything.
for _ in {1..20}; do [[ $(front) == $BUNDLE ]] && break; sleep 0.5; done
if [[ $(front) != $BUNDLE ]]; then echo "ABORT: frontmost is $(front), expected $BUNDLE. Nothing was inserted."; cleanup; exit 3; fi

printf '%s' "$SENTINEL" | pbcopy
$POST dictate-file "$AUDIO" "$MODE" "$BUNDLE"
sleep ${E2E_WAIT:-9}
RESULT=$(read_text)
CLIP_AFTER=$(pbpaste)
cleanup

echo "target:    $TARGET ($BUNDLE)"
echo "clip:      $CLIP ($MODE)"
echo "inserted:  ${RESULT:-<nothing>}"
[[ $CLIP_AFTER == $SENTINEL ]] && echo "clipboard: restored ✔" || echo "clipboard: CHANGED (now: ${CLIP_AFTER:0:60})"
[[ -n $RESULT ]] && exit 0 || exit 1
