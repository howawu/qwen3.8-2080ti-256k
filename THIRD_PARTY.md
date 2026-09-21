# Third-party components

This recipe integrates, but does not redistribute, third-party source trees or model weights. What it
does publish is the set of diffs that turn the upstreams into the exact engines the measurements were
taken on.

## Engines

- **KVMem / kvmem-llama.cpp:** <https://github.com/kvmem/kvmem-llama.cpp> — **no declared license upstream**.
  Pinned at `1734a2809bb0422da842d03a4734771ad9439ade`; the integration is published as
  [`patches/kvmem-outer-local-changes.patch`](patches/kvmem-outer-local-changes.patch) (10 files) and
  [`patches/llama-kvmem-current.patch`](patches/llama-kvmem-current.patch) (40 files in the llama.cpp
  submodule). Get the sources from upstream and replay the patches; see [engine notes](docs/ENGINE_NOTES.md).
- **llama.cpp:** MIT-licensed, <https://github.com/ggml-org/llama.cpp> — pinned at
  `16378d93f94012d4228c8c7683adce3f286aee5d`. Mode A is that tree plus
  [`patches/turing-mmvq-mmq-routing.diff`](patches/turing-mmvq-mmq-routing.diff), which is our own
  change to MIT-licensed code and is published under this repository's MIT license.

## Model and template files

- **Target model, DFlash2 drafter and multimodal projector** — all three from the `Q2-LynnStyle`
  directory of
  [`nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF`](https://huggingface.co/nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF).
  Apache-2.0 per the release page; the quantization, packaging and evaluation are the publisher's work.
  Exact byte sizes and SHA256 sums: [docs/MODELS.md](docs/MODELS.md).
- **DFlash2 drafter upstream:** z-lab / Inco AI, Apache-2.0 — <https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2>
  (mirror of `incoai/Qwen3.8-27B-DFlash2`). The GGUF used here is a conversion of it, not a re-license.
- **Chat template:** <https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates> (v22 generation).
  Third-party work, used unmodified, pointed at rather than vendored.

## Scope of this repository's license

The MIT license in this repository covers the original launcher scripts, configuration template,
documentation, benchmark summary, the Windows/Linux replay scripts and the Turing routing patch.
It does **not** relicense the KVMem sources the KVMem patches are diffed against, model weights, or
chat templates. Those remain under their own terms — treat the KVMem patches as interoperability
diffs and follow upstream when redistributing anything derived from them.
