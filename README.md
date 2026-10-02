# Voxara

A local-first voice interface for macOS. Hold a key, speak, release: your words appear in whatever text field has focus.

- **Dictation** (hold **Right ⌥**): voice → clean text. Fillers, stutters and spoken corrections are resolved; you are not rewritten.
- **Prompt Mode** (hold **Right ⌘**): voice → a structured instruction for an AI, written for Generic, Claude, ChatGPT or Claude Code. Intent is preserved, structure is improved, requirements are never invented.

English is primary, Bulgarian is first-class, and English technical terms inside Bulgarian speech are kept.
Speech recognition, cleanup and prompt building all run on this Mac. No account, no cloud, no audio saved.

## Run it

```sh
scripts/build-app.sh        # build, sign, install to ~/Applications/Voxara.app
open ~/Applications/Voxara.app
```

Voxara lives in the menu bar (waveform glyph). Open **Command Center** from the menu for status, history, models, shortcuts, per-app settings, vocabulary and settings. First launch shows a short setup guide.

Requirements: macOS 15+, Apple Silicon, Command Line Tools (full Xcode is **not** needed), and [Ollama](https://ollama.com) with a local model for AI cleanup and Prompt Mode (`brew install ollama && brew services start ollama && ollama pull qwen3:4b-instruct-2507-q4_K_M`). Without Ollama, dictation still works with rule-based cleanup and Prompt Mode builds a basic prompt from your words.

## Permissions

| Permission | Why |
|---|---|
| Microphone | Records only while you hold the shortcut; audio is discarded right after transcription. |
| Accessibility | Hears the global shortcut and types the result into the app you are using. Voxara never reads your screen. |

Run `scripts/create-signing-cert.sh` once: it makes a local self-signed code-signing identity, so macOS keeps these permissions across rebuilds. (Bundle identifier `com.daniel.voicetext` and the identity name are legacy names from before the rename; they are kept on purpose so permissions and settings carry over.)

## Models

- **Speech:** NVIDIA Parakeet TDT 0.6B v3 (via FluidAudio, Core ML). Multilingual with automatic language detection; ~0.1–0.4 s per clip on an M3. Chosen over Parakeet Ultra and Whisper large-v3-turbo after benchmarking; see `docs/reference-research.md`.
- **Intelligence:** Qwen3-4B-Instruct-2507 (Q4) through Ollama. Chosen over Gemma 3 4B on Prompt Mode fixtures (see the same doc).

Everything installed on the Mac, and how to remove it, is in `docs/system-dependencies.md`.

## Modes and shortcuts

Hold-to-talk: press and hold, speak, release. Pressing any other key during the hold cancels quietly, so shortcuts like Right ⌘+C still work. Taps under 250 ms and Esc are ignored. Change both under **Shortcuts** (modifier-only keys and combos supported; conflicts are flagged).

Prompt Mode depth: **Quick** (compact), **Structured** (default), **Deep** (phases, investigation, validation, definition of done when your request calls for them). Destinations are editable JSON profiles in `~/Library/Application Support/Voxara/PromptProfiles`.

Voxara can suggest a profile from the active app (Terminal and code editors → Claude Code, ChatGPT → ChatGPT, Claude → Claude). It only changes the profile and cleanup level, never the meaning of the hotkeys. Override per app under **Applications**.

## Privacy

| | |
|---|---|
| Speech transcription | Local |
| Transcript cleanup | Local (Ollama on `127.0.0.1`) |
| Prompt building | Local |
| Audio storage | Off |
| History | Text only, on this Mac, can be disabled or cleared |

No cloud provider is enabled. If one is ever added it will be opt-in and clearly marked.

## Development

```sh
scripts/test.sh                                   # unit tests (Swift Testing; wraps a CLT-only workaround)
swift build && .build/debug/vx-bench prompt qwen3:4b-instruct-2507-q4_K_M structured   # Prompt Mode fixtures vs the real model
.build/debug/vx-bench refine qwen3:4b-instruct-2507-q4_K_M                              # dictation cleanup fixtures
scripts/make-test-audio.sh                        # synthesize EN/BG test clips (macOS TTS)
.build/debug/Voxara --snapshot /tmp/shots         # render every UI page to PNG with sample data
```

Safe end-to-end insertion testing is described in `docs/testing.md`. **Never** test by typing into the app you are working in.

Layout: `Sources/VoxaraCore` (audio, speech, hotkeys, insertion, dictation, prompt compiler, storage; no UI), `Sources/VoxaraApp` (menu bar, overlay, Command Center, onboarding), `Sources/vx-bench`, `Tests/VoxaraCoreTests`, `Sources/VoxaraCore/Resources/PromptProfiles`, `scripts`, `docs`, `Brand`.

Toolchain note: with Command Line Tools only, SwiftUI's `@State` macro plugin is unavailable, so views use the `LocalState` typealias; and `swift test` needs the Swift Testing plugin path, which `scripts/test.sh` supplies.

## License

MIT, see [LICENSE](LICENSE). Third-party components and models are listed in [THIRD_PARTY.md](THIRD_PARTY.md).
