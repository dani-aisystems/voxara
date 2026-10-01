# What Voxara installs on this Mac

Everything below lives on this Mac only. There are no accounts and no cloud services.

| Item | Why Voxara needs it | Starts automatically? | Disk | How to remove |
|---|---|---|---|---|
| `~/Applications/Voxara.app` | The app itself (menu-bar utility). | Only if "Launch at login" is on. | ~20 MB | Quit Voxara, then `rm -rf ~/Applications/Voxara.app` |
| Parakeet TDT v3 speech model (`~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3`) | Local speech-to-text for English and Bulgarian. Downloaded once from Hugging Face on first launch. | Loaded by Voxara at launch. | 461 MB | `rm -rf ~/Library/Application\ Support/FluidAudio` |
| Ollama (`brew install ollama`) | Runs the local language model for transcript cleanup and Prompt Mode. | **Yes.** Homebrew LaunchAgent `sh.brew.ollama` (`RunAtLoad` + `KeepAlive`). It is idle until a request arrives, and the model unloads after 30 min without use. | ~70 MB binary | `brew services stop ollama && brew uninstall ollama` |
| Qwen3-4B Instruct 2507 (Q4_K_M) in Ollama | The local model used for cleanup and Prompt Mode. | Loaded on demand. | 2.5 GB | `ollama rm qwen3:4b-instruct-2507-q4_K_M` |
| Gemma 3 4B in Ollama | **Temporary.** Only for a one-time Prompt Mode comparison against Qwen; whichever model loses gets deleted. | No | 3.3 GB | `ollama rm gemma3:4b` |
| "VoiceText Local Signing" certificate (login keychain) | Self-signed code-signing identity. With a stable signature, macOS keeps the Microphone and Accessibility grants across rebuilds. It is trusted only for code signing, on this Mac. | n/a | — | `security delete-identity -c "VoiceText Local Signing"` |
| Voxara data (`~/Library/Application Support/Voxara/`) | Local history (text only; no audio), vocabulary, per-app preferences, editable prompt profiles. | n/a | small | Delete the folder, or use Clear History in Command Center |
| Settings (UserDefaults domain `com.daniel.voicetext`) | App preferences. | n/a | tiny | `defaults delete com.daniel.voicetext` |

## Legacy identifiers
The app was renamed from VoiceText to Voxara. The bundle identifier `com.daniel.voicetext`, the log subsystem and the signing identity name were kept on purpose: macOS ties the Microphone and Accessibility permissions and the stored settings to them. Renaming them would force you to grant permissions again.

## Full removal
```sh
pkill -x Voxara; rm -rf ~/Applications/Voxara.app
rm -rf ~/Library/Application\ Support/Voxara ~/Library/Application\ Support/FluidAudio
defaults delete com.daniel.voicetext
brew services stop ollama && brew uninstall ollama && rm -rf ~/.ollama
security delete-identity -c "VoiceText Local Signing"
tccutil reset All com.daniel.voicetext
```
