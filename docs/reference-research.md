# Reference research and decisions

Short record of what was studied, what was measured, and what was decided. Dated 2026-10.

## Reference projects

**FluidVoice** (altic-dev/FluidVoice, Swift, **GPLv3**). Studied for behaviour only; no code copied, because Voxara's licence is not GPL.
Ideas reimplemented independently:
- Global hotkey via an active `CGEventTap` on its own high-priority thread, re-enabled after timeouts, with a health check.
- Modifier-only push-to-talk state machine: another key pressed during the hold marks the press as "interrupted".
- Clipboard paste: full pasteboard snapshot, transient/concealed pasteboard types so clipboard managers ignore the text, explicit ⌘ down/V down/V up/⌘ up events, layout-aware V key code (`UCKeyTranslate`) so ⌘V works on Cyrillic layouts, restore only if `changeCount` is unchanged.
- Read-back verification of a paste through Accessibility.
Pitfalls it showed us to avoid: a new `AVAudioConverter` per buffer, delayed hotkey start-up, silently disabled event taps, a 6000-line settings file, and incomplete pastes in some editors.

**Voicebox** (jamiepine/voicebox, **MIT**). A voice studio (Tauri + Python sidecar) with dictation as one feature; Whisper-only, paste-only insertion.
Borrowed ideas: capture the focused element when the chord starts; hand activation back to the target app; set the ⌘ flag on the ⌘-down event (fixes Electron); a "text filter, not an assistant" refinement framing.
Its open issues are the failure modes guarded against here: refinement answering the transcript like a chat message, silently translating non-English speech, a 30 s cutoff, failed pastes into Claude.app, MLX crashes.

## Architecture decision
Native Swift + SwiftPM (menu-bar app). A Mac-only product benefits from direct access to Accessibility, CGEventTap, AVAudioEngine, non-activating panels, SMAppService and Keychain, and FluidAudio is Swift-native. Tauri would add a web view and a bridge to a Python/C speech engine for no gain. The `.app` is assembled by `scripts/build-app.sh` because full Xcode is not installed.

Toolchain constraints found (Command Line Tools only, Swift 6.4, macOS 27 SDK):
- `@State` is declared as a macro whose `SwiftUIMacros` plugin ships only with Xcode. Views use `typealias LocalState<V> = State<V>` (the underlying property-wrapper struct).
- Swift Testing needs `-plugin-path …/host/plugins/testing`; `scripts/test.sh` supplies it.
- MLX Swift cannot build its Metal shaders without Xcode, so local LLMs run through Ollama over HTTP.
- Apple's SpeechTranscriber and Foundation Models do not support Bulgarian.

## Speech engine: measured
Synthetic clips (macOS TTS, 11 clips: EN, BG, mixed BG+EN terms, numbers, names, long) on an M3 / 16 GB.

| Engine | Latency per clip | Notes |
|---|---|---|
| **Parakeet TDT v3 (Core ML)** | **0.06–0.30 s** (20 s of audio: 0.2 s) | Punctuation and capitalization built in. Automatic language detection. English terms inside Bulgarian come out as Cyrillic transliterations (дешбод, епи, бжитхаб). |
| Parakeet Ultra | 0.06–0.22 s | Similar; on the mixed sentences it produced mixed-script words ("Pull Reквеста"). No gain here, removed. |
| whisper large-v3-turbo (q5, whisper-cli) | 1.7–3.5 s (includes process start) | Latinizes some terms but misheard API as "App"; slower. Kept out of the app. |

Important finding: FluidAudio's `language:` hint is **not** used for Bulgarian. For Cyrillic languages it filters out every Latin letter, which would delete "dashboard" and "API".
Decision: Parakeet v3, language auto-detected, then the vocabulary layer (below) restores technical terms.

## Technical vocabulary
Transliteration of English terms is fixed after recognition, conservatively: exact aliases first, then sound-alike matching only for Cyrillic words the macOS Bulgarian dictionary does *not* know. Genuine Bulgarian words (компонент, сървър) are never replaced. Claude/ChatGPT are never matched by sound, because Bulgarian "клауд" is ordinary for "cloud" (found by a test). Result on real clips: "дешбод компонента" → "dashboard компонента", "деплой … полреквеста … бжитхаб" → "deploy … pull request-а … GitHub", "cloud code" → "Claude Code".

## Local language model: measured
Prompt Mode fixture suite (12–13 cases: coding, debugging, research, sales, writing, planning, business, Bulgarian, mixed, short, long). Scored on semantic preservation (concept groups with synonyms) and a forbidden-invention list, not on exact text. Few-shot examples in the extractor are deliberately *different* from the fixtures.

| Model | Structured | Via model (no fallback) | Avg time |
|---|---|---|---|
| **Qwen3-4B-Instruct-2507 Q4** | **12/12 (13/13 with the added long-Bulgarian case)**; Quick 12/12; Deep 12/12 | 12/12 | **~4.3 s** |
| Gemma 3 4B | 9/12 | 6/12 | 12.8 s |

Decision: Qwen3-4B; Gemma removed from the Mac. Local quality was sufficient, so no cloud provider was added.
Where the time goes: prompt processing is cheap (~0.45 s); output generation runs ~24 tokens/s, so Bulgarian (more tokens) is slower, ~4–8 s. Trimming empty JSON fields from the schema cut output ~40%.

Dictation cleanup (10 fixtures incl. self-corrections, mixed language, "do not answer questions", prompt-injection-style input): Qwen3-4B 10/10, ~1.2 s per AI pass; the AI pass only runs when the speech needs understanding (self-corrections or long dictations).

## How Prompt Mode stays honest
Separate stages: normalize → extract intent as schema-constrained JSON → **grounding** (drop items that cannot be traced to the speech) → deterministic rendering from an editable profile → verification (numbers, names and technical terms preserved, no invented numbers) → a **coverage backstop** that appends any spoken clause the prompt lost, under "Also mentioned" → graceful fallback to a structured version of the speaker's own words if the model is unavailable or fails verification. Profile "signal rules" add standard workflow lines (e.g. "verify with the project's own checks") only when the speech contains their trigger phrases.
Profile guidance is drawn from Anthropic's prompting best practices (explicit, scoped, tagged sections), Claude Code best practices (name the symptom, separate investigation from implementation, verify, keep changes small) and OpenAI's prompt guidance (outcome first, concise, no contradictions).

## Insertion
Paste is the default because it works in practically every app. Safeguards: the original app must be frontmost at the moment of ⌘V (otherwise the text stays on the clipboard); Chromium/Electron apps are switched into full accessibility mode so fields are detected and pastes verified; unverifiable or failed pastes keep the generated text on the clipboard and in history; clipboard contents are restored only if nothing else changed them.
