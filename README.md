# The Ultimate Qwen3.8-27B Deployment for RTX 2080 Ti

## 256K context · 67 tok/s · Q4_K_M-class quality on a 2018 Turing GPU

[中文说明](README_ZH.md)

A performance-first recipe that pushes a modified 22 GB RTX 2080 Ti close to its limit: a modern 27B hybrid model, a 1.9B DFlash2 drafter, 256K logical context and multimodal support—all on one old Turing card.

**This is the most aggressive and balanced Qwen3.8 deployment we know of for a single 22 GB RTX 2080 Ti.** It keeps speed, long context and answer quality in the same setup instead of sacrificing two to maximize one.

> **RTX 2080 Ti 22 GB · 256K context · 67 tok/s simple workloads · 45–48 tok/s daily use · DFlash2 + near-free n-gram reuse**

![Pelican bicycle animation generated as a creative coding test](assets/pelican-bike.gif)

## What is unusual about this setup?

- **Old hardware, modern workload:** a 27B hybrid model plus a 1.9B DFlash2 drafter on `sm_75`.
- **256K logical context:** KVMem keeps a 112,640-token target-KV working set on the GPU and retrieves older blocks instead of pretending all 256K KV is resident in 22 GB.
- **Useful interactive speed:** about 45–48 tok/s in normal operator use; a six-prompt simple code test measured a 66.92 tok/s median.
- **Two speculative paths:** DFlash2 handles novel text; `ngram-mod` catches repeated code, templates and conversation fragments.
- **Near-free repeated-context acceleration:** in the intended warm-repeat demo, n-gram reuse raised a code request from 70.39 to 227.65 tok/s median (3.23×). The target model still verifies candidates, so “free” means no neural draft pass on a hit—not zero GPU work.
- **Quality-oriented low-bit recipe:** the mixed Q2 model was selected for operator-perceived quality comparable to Q4_K_M while fitting the target, drafter and long-context caches on one card. This is a qualitative assessment, not a perplexity equivalence claim.
- **Less unproductive reasoning:** an EfficientThink/SimPO model recipe plus `reasoning-effort=low` reduces overthinking without globally disabling reasoning.
- **Cross-request prefix reuse:** a checkpoint fix reduced a measured 11K-token follow-up prefill from 21.7 s to 0.356 s.
- **Turing-aware verifier routing:** the local MMVQ→MMQ route improved the MATLAB workload from 35.72 to 44.87 tok/s.

## Two run modes, one card

The repository documents **two launch configurations**, both of which bind `127.0.0.1:8080` and consume the same model files. A 22 GB card fits one of them at a time, so sharing the port means every client, proxy and IDE integration keeps working whichever one is running.

| Mode | Engine | Context | Launcher | Character |
|---|---|---:|---|---|
| **A** | upstream llama.cpp + DFlash2 | 131,072 | [`scripts/start-llama.ps1`](scripts/start-llama.ps1) | daily driver: lowest latency per token, most VRAM headroom |
| **B** | KVMem | 262,144 logical | [`scripts/start-kvmem.ps1`](scripts/start-kvmem.ps1) | long-context mode: 112,640-token physical working set, older context retrieved |

Every flag, environment variable, VRAM item and known pitfall is written down in **[docs/LAUNCH_PARAMS.md](docs/LAUNCH_PARAMS.md)**, including the eleven things that most often break a reproduction.

## Measured envelope

**Mode A (llama.cpp + DFlash2, 128K), code prompt, `temp=0`:**

| Workload | Result |
|---|---:|
| Short-context decode | **64.7 tok/s** |
| Decode at 125K context | **30.8 tok/s** |
| Prefill | 361–380 tok/s |
| Turing verifier routing (MATLAB task) | 35.72 → **44.87 tok/s** |

**Mode B (KVMem, 256K logical):**

| Workload | Result |
|---|---:|
| Simple code generation, six independent cold prompts | **66.92 tok/s median** (56.35–74.98) |
| MATLAB Kalman task | **44.87 tok/s** |
| Daily interactive use | **about 45–48 tok/s**, content dependent |
| Same code request with warm n-gram state | **227.65 tok/s median**, 3.23× vs first run |
| Cached 11K-token follow-up prefill | **0.356 s**, 61× vs broken-cache baseline |

Numbers belong to the mode that produced them; they are not interchangeable. See [measurement conditions and claim boundaries](docs/BENCHMARKS.md).

## Memory layout

```text
                              mode A (128K)      mode B (256K logical)
target weights                  12.11 GiB          12.11 GiB
draft weights                    1.06 GiB           1.06 GiB
target KV                    q8_0/q8_0 @128K    112,640-token pool, 3.65 GiB
draft KV                     small, f16         262,144 x 10.6 KiB, 2.60 GiB
free headroom to keep          >= 0.8 GiB         >= 0.8 GiB
```

The 256K claim is a **logical context capacity**, not 256K tokens of fully resident target KV.

## What to download

Weights and binaries are not redistributed here. Three files are needed, all from one GGUF release — the **`Q2-LynnStyle`** directory of
[`nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF`](https://huggingface.co/nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF):

| File | Role | SHA256 (first 16) |
|---|---|---:|
| `Qwen3.8-27B-EfficientThink-SimPO-Q2-LynnStyle.gguf` | target model (12.11 GiB) | `8a84f7ef93b01c63` |
| `dflash2-qwen38-27b-Q4_K_M.gguf` | DFlash2 drafter (1.06 GiB) | `e83676f81b660433` |
| `mmproj-Qwen3.8-27B-Q4_K_M.gguf` | vision projector, optional (0.50 GiB) | `0d22c439a59fb0ff` |

A fourth, non-model file matters for reproduction: the chat template from
[`froggeric/Qwen-Fixed-Chat-Templates`](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates) (v22 generation), because that is what implements `reasoning_effort`.

**[docs/MODELS.md](docs/MODELS.md)** has the full file list, byte sizes, complete checksums, the `hf download` command, the manifest facts that drive the tuning (mixed `IQ3_S`/`IQ4_XS` tensor mix, text-only/no-MTP target) and the license notes.

## Quick start

Requirements:

- Windows 11
- NVIDIA Turing GPU with 22 GB VRAM (validated on RTX 2080 Ti 22 GB)
- Mode A: `llama-server.exe` from llama.cpp `16378d9` built with the [Turing routing patch](patches/turing-mmvq-mmq-routing.diff)
- Mode B: the KVMem engine — clone upstream and replay the two patches in `patches/` (one command on Windows: `scripts\bootstrap-engine.ps1 -Build`)
- Target GGUF, DFlash2 drafter, optional mmproj and chat template

```powershell
# 1. engine: upstream KVMem + the published patches (mode B; mode A additionally
#    needs llama.cpp 16378d9 + patches/turing-mmvq-mmq-routing.diff)
git clone https://github.com/kvmem/kvmem-llama.cpp
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-engine.ps1 -Build

# 2. configuration
Copy-Item .\config.example.ps1 .\config.ps1
notepad .\config.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\check-config.ps1

# 3. run one of the two modes
powershell -ExecutionPolicy Bypass -File .\scripts\start-llama.ps1   # Mode A: 128K, llama.cpp + DFlash2
powershell -ExecutionPolicy Bypass -File .\scripts\start-kvmem.ps1   # Mode B: 256K logical, KVMem
```

Run a start script again to stop the service it started. It refuses to kill another process that already owns the port.

## Core configuration

**Mode A — 128K daily driver:**

```text
--ctx-size 131072 --parallel 1
--n-gpu-layers all --fit off
--flash-attn on
--cache-type-k q8_0 --cache-type-v q8_0
--spec-type draft-dflash,ngram-mod
--spec-draft-n-max 6
--spec-draft-type-k f16 --spec-draft-type-v f16
--mmproj ... --mmproj-device none --no-mmproj-offload
--reasoning on --reasoning-effort low
--temp 0.7 --top-k 20 --top-p 0.8
-b 1024 -ub 512 --threads 8 --threads-batch 8
GGML_MMVQ_MAX=4
GGML_MMVQ_ALL=1
```

**Mode B — 256K logical:**

```text
-c 262144
--kvmem-method retrieval
--kvmem-budget 96256
--kvmem-gen-reserve 16384
--kv-dtype q8_0
--spec-type draft-dflash,ngram-mod
--spec-draft-n-max 6
-b 1024 -ub 512
GGML_MMVQ_MAX=4
GGML_MMVQ_ALL=1
```

## Visual/creative test

The pelican animation was produced from a prompt asking the local model to create an animated SVG. The model generated the animation code; the GIF is its rendered output. Details: [assets/pelican-bike.md](assets/pelican-bike.md).

## Important boundaries

- Model weights and binaries are not included.
- The two run modes are measured separately; mixing their figures overstates or understates both.
- The KVMem outer repository declares no license, so its sources are not bundled here. The integration is published instead as replayable diffs against pinned upstream commits ([`patches/`](patches/README.md)) with a one-command replay, and the replayed tree is byte-identical to the one the measurements were taken on. The Turing routing patch is our own change to MIT-licensed llama.cpp.
- Speed changes with speculative acceptance rate. Repeated-context numbers are not general prose throughput.
- The Q4_K_M comparison and reduced-overthinking statement are operator evaluations, clearly separated from measured throughput.
- Long-context retrieval can trade exact full-history attention for a bounded GPU working set.
- The n-gram speedup was measured with a *repeated* prompt. Repeating one prompt keeps the lookup table warm across requests and inflates the number; use independent cold prompts when benchmarking.

## License

Original scripts and documentation in this repository are MIT-licensed. Third-party engines and models keep their own terms; see [THIRD_PARTY.md](THIRD_PARTY.md).
