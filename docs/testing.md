# Testing Voxara safely

## Rule
Tests must never type into an app you are using. Every automated insertion test goes through a throwaway target and is gated twice: the script verifies the frontmost app (or browser tab) before posting, and Voxara itself refuses unless the expected bundle ID is frontmost. The text injector also refuses to paste unless the original app is frontmost at the moment of ⌘V, keeping the text on the clipboard instead.

## Setup (once)
```sh
defaults write com.daniel.voicetext EnableDebugCommands -bool true   # enables the debug hook; relaunch Voxara
scripts/make-test-audio.sh                                            # synthetic EN/BG clips in bench/audio (gitignored)
```

## Automated insertion tests
```sh
scripts/e2e-insert.sh testbench|textedit|terminal|brave|safari  <clip>  <dictation|prompt>
# e.g. scripts/e2e-insert.sh brave bg-mixed-deploy dictation
```
- `textedit`: new throwaway document, text read back via AppleScript.
- `terminal`: new window running `cat > /tmp/voxara-e2e.txt`, result read from the file.
- `brave` / `safari`: a brand-new window with a local page that mirrors its textarea into the tab title; aborts unless the active tab is that page.
- `testbench`: Voxara's own "Test Bench" window.
Each run also checks that the clipboard was restored.

Aborts are expected when something else takes focus mid-run (nothing is inserted). Just rerun.

## Live hotkey test
```sh
scripts/live-hotkey-test.sh dictation 6     # synthetic Right ⌥ hold, real microphone, test mode ON for the whole run
```
Test mode (Settings → Advanced, or the script) restricts insertion to the Test Bench window. The microphone hears the room, so the text is whatever was audible.

## Manual checklist (needs you)
ChatGPT.app, Claude.app, Notion, VS Code/Antigravity and Messages are not automated, because writing into your real conversations or documents is not safe to do unattended. In each: click in the input, hold Right ⌥, say a sentence, release. Confirm the text appears, nothing is sent, and your clipboard is unchanged. Repeat with Right ⌘ for Prompt Mode (Claude Code profile in the editor/terminal).

## Unit tests and benchmarks
`scripts/test.sh` runs the unit tests. `vx-bench prompt` and `vx-bench refine` run the fixtures against the real local model and score semantic preservation.
