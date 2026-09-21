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

## Measured envelope

| Workload | Result |
|---|---:|
| Simple code generation, six independent cold prompts | **66.92 tok/s median** (56.35–74.98) |
| MATLAB Kalman task | **44.87 tok/s** |
| Daily interactive use | **about 45–48 tok/s**, content dependent |
| Same code request with warm n-gram state | **227.65 tok/s median**, 3.23× vs first run |
| Cached 11K-token follow-up prefill | **0.356 s**, 61× vs broken-cache baseline |

See [measurement conditions and claim boundaries](docs/BENCHMARKS.md).

## Memory layout

```text
target weights                         12.11 GiB
draft weights                           1.06 GiB
target KV: 96,256 + 16,384 tokens       3.65 GiB
draft KV at 262,144 logical tokens      2.60 GiB
recommended free headroom              >= 0.8 GiB
```

The 256K claim is a **logical context capacity**, not 256K tokens of fully resident target KV.

## Quick start

Requirements:

- Windows 11
- NVIDIA Turing GPU with 22 GB VRAM (validated on RTX 2080 Ti 22 GB)
- A compatible `llama-kvmem-server.exe` built for `75-real`
- Target GGUF, DFlash2 drafter, optional mmproj and chat template

```powershell
Copy-Item .\config.example.ps1 .\config.ps1
notepad .\config.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\check-config.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\start-kvmem.ps1
```

Run the start script again to stop the service. It refuses to kill another process that already owns the port.

## Core configuration

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
- The KVMem outer repository currently has no declared license, so this repo does not redistribute its source or the cumulative derivative patch. See [engine notes](docs/ENGINE_NOTES.md).
- Speed changes with speculative acceptance rate. Repeated-context numbers are not general prose throughput.
- The Q4_K_M comparison and reduced-overthinking statement are operator evaluations, clearly separated from measured throughput.
- Long-context retrieval can trade exact full-history attention for a bounded GPU working set.

## License

Original scripts and documentation in this repository are MIT-licensed. Third-party engines and models keep their own terms; see [THIRD_PARTY.md](THIRD_PARTY.md).
