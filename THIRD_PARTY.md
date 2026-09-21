# Third-party components

This recipe integrates, but does not redistribute:

- **KVMem / kvmem-llama.cpp:** <https://github.com/kvmem/kvmem-llama.cpp> (no declared license upstream — see [engine notes](docs/ENGINE_NOTES.md))
- **llama.cpp:** MIT-licensed, <https://github.com/ggml-org/llama.cpp>
- **Target model, DFlash2 drafter and multimodal projector** — all three from the `Q2-LynnStyle` directory of
  [`nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF`](https://huggingface.co/nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF).
  Apache-2.0 per the release page; the quantization, packaging and evaluation are the publisher's work.
  Exact byte sizes and SHA256 sums: [docs/MODELS.md](docs/MODELS.md).
- **DFlash2 drafter upstream:** z-lab / Inco AI, Apache-2.0 — <https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2>
  (mirror of `incoai/Qwen3.8-27B-DFlash2`). The GGUF here is a conversion of it, not a re-license.
- **Chat template:** <https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates> (v22 generation). Third-party work;
  used unmodified, pointed at rather than vendored.

The Turing MMVQ→MMQ routing patch in [`patches/`](patches/) is our own change to MIT-licensed llama.cpp and is
published under the same MIT terms as the rest of this repository — see
[docs/ENGINE_NOTES.md](docs/ENGINE_NOTES.md) for what it changes and why.

The MIT license in this repository applies only to the original launcher scripts, configuration template,
documentation, benchmark summary and patch stored here. It does not relicense model weights, chat templates or
third-party engines.
