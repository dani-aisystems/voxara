# Implementation status

Last updated: 2026-10-02

## DONE

- Dictation: Right ⌥ hold → Parakeet v3 (EN + BG, ~0.1–0.4 s) → rules + local-model cleanup → paste with clipboard restore. Verified end to end with the gated harness in TextEdit, Terminal, Brave, Safari and Voxara's own test bench (EN, BG, mixed, self-correction); live key-hold + real microphone verified in test mode.
- Cleanup wired into real dictation: deterministic pass always, Qwen3-4B only when the speech needs understanding; output guards reject answering, translating, summarizing or inventing; falls back to rules with a notice.
- Technical vocabulary: editable list + conservative sound-alike restoration (dashboard, API, GitHub, pull request, Claude Code …); genuine Bulgarian words are never replaced.
- Prompt Mode: PromptCompiler (extract → ground → render → verify → coverage backstop → fallback), profiles Generic / Claude / ChatGPT / Claude Code as editable JSON, presets Quick / Structured / Deep. Qwen3-4B passes 13/13 fixtures on Structured and 12/12 on Quick and Deep via `vx-bench prompt`; Gemma 3 4B lost and was removed.
- App: Voxara branding and icon, design tokens, non-activating overlay, menu bar, Command Center (Overview, Dictation, Prompt Mode, Vocabulary, History, Applications, Models, Shortcuts, Settings), onboarding, per-app preferences with conservative suggestions, text-only history, privacy indicators, test mode and test bench.
- Safety: insertion refuses unless the original app is frontmost at ⌘V; Chromium/Electron apps are put into full accessibility mode so fields are detected and pastes verified; failed pastes keep the text on the clipboard and in history; debug dictation refuses unless the expected app is frontmost.
- 128 unit tests; fixture suites for dictation cleanup and Prompt Mode.

## IN PROGRESS

- Final validation pass and review.

## NEXT

- Manual checks only you can do: ChatGPT.app, Claude.app, Notion, Antigravity/VS Code, Messages (see `docs/testing.md`), and real speech in English, Bulgarian and mixed.
- Launch at login (SMAppService) and the shortcut recorder are implemented but untested.
- Optional later: toggle (tap) mode, Keychain-backed cloud providers (none enabled), dedicated vocabulary boosting inside the speech model.

## BLOCKERS

- None.

## KNOWN ISSUES

- Prompt Mode takes ~2–8 s depending on length and language (Bulgarian output is token-heavy at ~24 tokens/s on this Mac); dictation without an AI pass takes well under a second.
- Parakeet still hears "Claude Code" as "cloud code" until the alias fixes it (it does, via vocabulary); other brand names need adding to Vocabulary.
- A live-microphone test hears the room, not the test clip; speaker-to-mic loopback is unreliable here.
- Other apps on this Mac regularly take focus during long runs; the harness aborts safely when that happens.
