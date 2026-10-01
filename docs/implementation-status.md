# Implementation status

Last updated: 2026-10-01

## DONE
- Environment audit: macOS 27.0, M3 / 16 GB, CLT-only Swift 6.4 (no Xcode).
- Architecture: native Swift + SwiftPM, FluidAudio (Parakeet) for STT. Builds with CLT only.
- Local self-signed code-signing identity ("VoiceText Local Signing") so TCC grants persist.
- STT benchmark corpus (EN, BG, mixed) and Parakeet v3 / Ultra / whisper-turbo runs on it.
- Walking skeleton, verified on this Mac:
  - Right ⌥ / Right ⌘ hold-to-talk via CGEventTap (state machine unit-tested).
  - Real microphone capture → Parakeet → paste into TextEdit, clipboard restored.
  - Bulgarian (Cyrillic) text inserted correctly.
  - `scripts/build-app.sh` builds, signs and installs `~/Applications/VoiceText.app`.

## IN PROGRESS
- Phase 3: reliable dictation (cleanup, overlay, error handling, model management).

## NEXT
- DeterministicCleaner + spoken commands (EN/BG), LLM refiner with output guards.
- Floating overlay, permission onboarding.
- Prompt Compiler, profiles, local-model selection (Ollama).
- Settings, history, menu.
- Hardening in browser, ChatGPT/Claude apps, Terminal.

## KNOWN ISSUES
- Speaker→mic loopback test did not capture the played clip (picked up ambient speech instead), so
  mic accuracy on a known clip is unverified; file-based pipeline runs are verified.
- Parakeet transliterates English terms inside Bulgarian speech (e.g. "dashboard" → "дешбод"); needs
  vocabulary correction in the refiner.
- `swift test` needs the `-plugin-path` workaround under CLT; use `scripts/test.sh`.
