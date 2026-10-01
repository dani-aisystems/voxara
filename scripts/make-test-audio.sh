#!/bin/zsh
# Synthesizes the STT benchmark corpus with macOS TTS into bench/audio (gitignored).
# Usage: scripts/make-test-audio.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p bench/audio

python3 - <<'PY'
import json, subprocess
for clip in json.load(open("bench/stt-corpus.json")):
    out = f"bench/audio/{clip['id']}.wav"
    subprocess.run(
        ["say", "-v", clip["voice"], "-o", out, "--data-format=LEI16@16000", clip["text"]],
        check=True,
    )
    print("wrote", out)
PY
