# Model files and where to get them

Everything in this repository is a recipe: weights and binaries are **not**
redistributed here. This page lists exactly which files the launchers expect,
where they come from, and the checksums to verify them against, so that a
download from any mirror can be proven identical to the one the numbers were
measured on.

## 1. Target model, drafter and vision projector

All three come from one GGUF release: **`Q2-LynnStyle`** in

<https://huggingface.co/nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF>

```bash
pip install -U "huggingface_hub[cli]"
hf download \
  nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF \
  --include "Q2-LynnStyle/*" --local-dir ./models
```

| File (under `Q2-LynnStyle/`) | Role | Bytes | GiB | SHA256 |
|---|---|---:|---:|---|
| `Qwen3.8-27B-EfficientThink-SimPO-Q2-LynnStyle.gguf` | **target model** — text-only, no welded MTP head | 12,999,977,600 | 12.11 | `8a84f7ef93b01c6376a19fc80fd9df849d23d5785e5953bd3e4fc278d5d21922` |
| `dflash2-qwen38-27b-Q4_K_M.gguf` | **DFlash2 drafter** used by both run modes | 1,143,006,720 | 1.06 | `e83676f81b6604331d02e004a50689eded7fa905c7e83468e5a376cc27abcad4` |
| `mmproj-Qwen3.8-27B-Q4_K_M.gguf` | **vision projector** (optional; the launchers use it if present) | 522,293,024 | 0.49 | `0d22c439a59fb0ffb784530babc4f03a10581484b7ac68d9a5707fc0d7675d48` |
| `dflash2-qwen38-27b-Q8_0.gguf` | alternative, larger DFlash2 drafter (not used by default) | 2,056,414,720 | 1.92 | `1086ea5d44e9d7b3ee1978ce322c01f96d9c1086bd5e73d89397be7a2af1335a` |
| `mtp-Qwen3.8-27B-Q4_0.gguf` | MTP drafter, **not usable with this target** (the Q2 build ships no `nextn` head) — listed for completeness | 1,680,271,648 | 1.56 | `051a1764cff8c4f3ee6ae8b00593a0364c7539c67fa50ffc58f3f96509fca38e` |
| `mtp-Qwen3.8-27B-Q8_0.gguf` | as above | 3,164,006,688 | 2.95 | `cbf60a0c48b431bb61f1d49b8948dc88ac29c398d6dbdbbb2e6e89ef77eacc9a` |

Verify (the repository ships its own `SHA256SUMS`; `--ignore-missing` lets you
check a partial download):

```bash
cd models/Q2-LynnStyle
sha256sum --ignore-missing -c SHA256SUMS
```

The manifest in the same directory (`manifest.json`) records the quantization
method, the per-tensor-type counts and the evaluation record published with this
tier. Two facts from it matter for reproduction:

- The build is a **mixed-precision GSQ-IQ-RCO** map of a frozen source, not a
  single-format quant: 268 `IQ3_S`, 88 `IQ4_XS`, 85 `Q4_K`, 32 `IQ3_XXS`,
  21 `IQ2_S`, plus `Q5_K`/`Q2_K`/`F32` scales. This is why
  `GGML_MMVQ_ALL=1` is required in mode A rather than optional — see
  [LAUNCH_PARAMS.md](LAUNCH_PARAMS.md) §1.3.
- The artifact is declared **text-only / no-MTP** (`gguf: v3 / qwen35 / 64 layers
  / 851 tensors / visual 0 / mtp 0`). Speculative decoding with this target means
  a **DFlash2 sidecar**, not MTP.

### Choosing between the two DFlash2 drafts

`Q4_K_M` (1.06 GiB) is what all numbers in this repository were taken with.
`Q8_0` (2.06 GiB) is the higher-precision option and costs ~1 GiB of VRAM; on a
22 GB card already running at ≥0.8 GiB free that is a real trade, so only switch
after re-reading the headroom.

### DFlash2 upstream

The drafter is a GGUF conversion of the DFlash2 block-diffusion drafter for
`Qwen/Qwen3.8-27B`, published by Inco AI / z-lab under Apache-2.0:
<https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2> (mirror of
`incoai/Qwen3.8-27B-DFlash2`). It is not a standalone language model: loaded
without a target it fails by design. Your engine must support
`--spec-type draft-dflash` and `--spec-draft-model` for this to work at all.

## 2. Chat template

Both launchers pass an explicit template instead of relying on the one embedded
in the GGUF:

- Source: **`froggeric/Qwen-Fixed-Chat-Templates`** — <https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates>
  (v22 generation; one `chat_template.jinja` covers the Qwen 3.5/3.6/3.8 sizes).
- The file used for the published numbers identifies itself as
  `qwen3.8-froggeric-v22.4` (first line of the template) and has
  SHA256 `c47c82b0544752d454f4e427228d9d9d8c3df64c9e446cbd0229362f67948009`.
- Why it matters here: this template is what implements the `reasoning_effort`
  levels (and the client-side aliases `high/max → xhigh`, `minimal → low`,
  `none → thinking off`), and it defaults to `medium` instead of the model's
  `xhigh`. Both launchers pass `--reasoning-effort low` on top of it.
- If you skip the template entirely you get the model's own default, which is the
  highest reasoning tier: 70–85% of generated tokens go into the thinking block
  and a small output budget can be consumed entirely (measured: finish reason
  `length` with **zero** answer tokens). If you use a different template, change
  reasoning depth at the client instead and re-check the defaults before
  comparing speed.

## 3. Licenses

- The Q2-LynnStyle release and its manifest: Apache-2.0 (per the release page).
- DFlash2 drafter: Apache-2.0, from the releases linked above.
- Quantization, packaging and evaluation of these GGUFs are the publisher's work;
  follow their terms. This repository only points at them. See
  [THIRD_PARTY.md](../THIRD_PARTY.md).
