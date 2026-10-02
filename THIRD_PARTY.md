# Third-party software and models

Voxara's own code is MIT licensed (see `LICENSE`). It uses, but does not bundle, the following. Check each licence before redistributing.

| Component | Licence | How it is used |
|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache-2.0 | Swift package that runs the speech model through Core ML (linked at build time). |
| NVIDIA Parakeet TDT 0.6B v3 (Core ML build by FluidInference) | CC-BY-4.0 | Speech model, downloaded on first launch to `~/Library/Application Support/FluidAudio`. |
| [Ollama](https://github.com/ollama/ollama) | MIT | Local runtime for the language model; installed separately by the user. |
| Qwen3-4B-Instruct-2507 | Apache-2.0 | Default local language model; pulled by the user with `ollama pull`. |

Ideas studied from Voicebox (MIT) and FluidVoice (GPLv3) are described in `docs/reference-research.md`. No FluidVoice source code was copied.
