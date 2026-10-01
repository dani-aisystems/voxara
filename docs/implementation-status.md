# Implementation status

Last updated: 2026-10-01

## DONE

- Native Swift/SwiftPM app built with Command Line Tools only; signed with a local identity so permission grants persist.
- Speech: Parakeet TDT v3 via FluidAudio (EN + BG, ~0.1–0.3 s per clip). Benchmarked against Parakeet Ultra and whisper large-v3-turbo.
- Right ⌥ / Right ⌘ hold-to-talk (CGEventTap state machine, unit-tested).
- Clipboard-safe paste insertion; EN and BG verified in TextEdit.
- Dictation refinement components (cleaner, spoken commands, self-correction detection, output guards, Ollama refiner). Qwen3-4B passes 10/10 fixtures in `vx-bench refine`.
- Rebranded to Voxara (app bundle, targets, strings). The legacy bundle ID was kept, so the grants survived (verified).
- `docs/system-dependencies.md` documents everything installed on the Mac.

## IN PROGRESS

- Safe insertion harness (test mode, expected-target guard).

## NEXT

- Wire refinement into real dictation (settings, router, warm-up).
- Vocabulary / term repair for English terms in Bulgarian speech.
- Floating overlay.
- Prompt Compiler, profiles, presets, fixtures, and the Qwen vs Gemma benchmark.
- Command Center (Overview, History, Models, Applications, Shortcuts, Settings), onboarding.
- Real-app validation and final review.

## BLOCKERS

- None. The logo image is still to come from Daniel (`Brand/logo/`); the app uses a symbol until then.
