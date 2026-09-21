# Launch parameters

Two run modes are documented here. They are **mutually exclusive**: both bind
`127.0.0.1:8080` and one 22 GB card holds only one of them, so clients, proxies
and IDE integrations never have to be reconfigured — whichever launcher is
running owns the port.

| Mode | Engine | Context | Role |
|---|---|---:|---|
| **A — upstream llama.cpp + DFlash2** | `llama-server.exe` built from upstream llama.cpp plus the Turing routing patch | 131,072 | daily driver: lowest latency per token, smallest footprint, most headroom |
| **B — KVMem** | `llama-kvmem-server.exe` built from KVMem + llama.cpp `16378d9` | 262,144 logical | long-context mode: 112,640-token GPU working set, older context retrieved |

Both modes consume the same model files (see [MODELS.md](MODELS.md)) and the
same chat template. Mode A is the configuration that produces the short-context
numbers; mode B is the one behind the 256K headline. Do not mix measurements
from the two.

---

## 0. Engine prerequisites

Both engines are built from llama.cpp `16378d93f94012d4228c8c7683adce3f286aee5d`
with CUDA, `GGML_CUDA_FA_ALL_QUANTS=ON` (the KV types used below are not in the
default flash-attention quant set) and, for mode A, the Turing routing patch in
[`patches/turing-mmvq-mmq-routing.diff`](../patches/turing-mmvq-mmq-routing.diff):

```bat
cmake -S llama.cpp -B build -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON ^
  -DCMAKE_CUDA_ARCHITECTURES=75-real ^
  -DGGML_NATIVE=ON -DGGML_CUDA_FA_ALL_QUANTS=ON ^
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=ON
```

`75-real` rather than `75` keeps the build from emitting PTX the card is too old
to JIT; the local 8080 build also compiles `86` because the same tree is shared
with another machine. Mode B additionally needs the KVMem integration listed in
[ENGINE_NOTES.md](ENGINE_NOTES.md) — the flags below do not exist in stock
llama.cpp.

---

## 1. Mode A — upstream llama.cpp + DFlash2 (128K)

### 1.1 Command line

```text
llama-server.exe ^
  --model  <Q2-LynnStyle.gguf> ^
  --alias  qwen3.8-local ^
  --host   127.0.0.1 --port 8080 ^
  --ctx-size 131072 ^
  --parallel 1 ^
  --n-gpu-layers all ^
  --fit off ^
  --mmproj <mmproj-Qwen3.8-27B-Q4_K_M.gguf> --mmproj-device none --no-mmproj-offload ^
  --flash-attn on ^
  --cache-type-k q8_0 --cache-type-v q8_0 ^
  --spec-type draft-dflash,ngram-mod ^
  --spec-draft-model <dflash2-qwen38-27b-Q4_K_M.gguf> ^
  --spec-draft-n-max 6 ^
  --spec-draft-type-k f16 --spec-draft-type-v f16 ^
  --jinja --chat-template-file <chat_template.jinja> ^
  --reasoning on --reasoning-effort low ^
  --temp 0.7 --top-k 20 --top-p 0.8 ^
  --batch-size 1024 --ubatch-size 512 ^
  --threads 8 --threads-batch 8
```

with the environment of the server process set first:

```text
GGML_MMVQ_MAX=4
GGML_MMVQ_ALL=1
```

`scripts/start-llama.ps1` builds exactly this line from `config.ps1` (argument
order is not significant; the launcher appends the optional projector flags at
the end). The table below explains every value so it can be re-derived rather
than copied blindly.

### 1.2 What each value does

| Flag | Value | Why this value |
|---|---|---|
| `--model` | Q2-LynnStyle GGUF | 12.11 GiB mixed Q2, the largest quality-per-gigabyte build that leaves room for KV + drafter + headroom on a 22 GB card. |
| `--alias` | `qwen3.8-local` | A stable client-side model name. Mode A and mode B share it, so switching modes is invisible to whatever talks to the API. |
| `--host` / `--port` | `127.0.0.1` / `8080` | Loopback only. Port 8080 is deliberate: mutual exclusion is enforced by the port, and clients never move. |
| `--ctx-size` | `131072` | 128K is the largest verified context for this model. Beyond ~130K tokens the model is reported to emit EOS early ([llama.cpp #27756](https://github.com/ggml-org/llama.cpp/issues/27756), per-layer accumulation error in the Gated DeltaNet recurrent state). It did not reproduce here up to 170K, but that test used highly repetitive filler — the easiest case. Treat >128K as unverified and use mode B when you genuinely need more. |
| `--parallel` | `1` | One slot. A second slot doubles KV for a card that is already bandwidth-bound; concurrency does not add throughput here. |
| `--n-gpu-layers` | `all` | Full offload (`-ngl 99` is equivalent). |
| `--fit` | `off` | Disables llama.cpp's automatic memory fitter. Left on, it silently shrinks context/layers when the budget is tight — i.e. it would change the configuration being measured. The VRAM budget here is tuned by hand (see §3). |
| `--mmproj`, `--mmproj-device none`, `--no-mmproj-offload` | mmproj GGUF | Keeps the 522 MB vision projector in **host** memory. `--mmproj-offload` defaults to enabled and overrides `--mmproj-device none`; measured A/B with the projector on the GPU was **21,908 MiB vs 20,375 MiB** used (≈1.5 GiB). With the flag the cost is ~23 MiB and image input still works. Dropping this flag is the single easiest way to fall into the low-headroom regime. |
| `--flash-attn` | `on` | Requires the `q8_0` KV types used here and is the path the Turing routing patch affects. |
| `--cache-type-k` / `-v` | `q8_0` / `q8_0` | KV read cost grows with context depth: at 128K, `q4_0` KV is ~18% of the per-token byte budget and `q8_0` ~35% — measurable only at depth, and worth the ~2 GiB. On the ~14 GiB IQ4 weight set the same choice does not fit, which is why this is tied to the 12.11 GiB Q2 weights. If VRAM gets tight, drop to `q4_0/q4_0` first (saves ~2 GiB) before touching context or weights. |
| `--spec-type` | `draft-dflash,ngram-mod` | Two proposers, priority hardcoded in the engine: `ngram*` runs before `draft*`. `ngram-mod` fires only on genuinely repeated content (it uses engine defaults `n_match=24`, `n_min=48`, `n_max=64`; every tuning direction measured worse) and **abstains otherwise**, so on free-flowing text DFlash2 behaves exactly as it does alone. On repetitive content it returns 64-token drafts and lifts throughput ~2.4×. Revert to drafter-only with `draft-dflash`. |
| `--spec-draft-model` | `dflash2-qwen38-27b-Q4_K_M.gguf` | 1.06 GiB block-diffusion drafter (1.92B). The Q8_0 variant also works and is 2.06 GiB; the Q4_K_M one is what all numbers here use. |
| `--spec-draft-n-max` | `6` | The n4–n8 curve is flat, not peaked (53.4 / 53.4 / **54.9** / 54.6 / 53.0 tok/s), and n6 is the most stable point (54.8–55.0, first and second half agreeing to 0.1 tok/s). Stability over peak matters for batch work. This optimum belongs to the *DFlash2 scheme*: block diffusion does not lose acceptance with depth (0.814 at n4 → 0.698 at n8), the opposite of MTP (0.83 → 0.39), whose knee sits at n2 — retune after changing drafter. |
| `--spec-draft-type-k` / `-v` | `f16` / `f16` | The drafter's own KV cache is small and is kept at full precision. |
| `--jinja` + `--chat-template-file` | `chat_template.jinja` | Needed for per-request reasoning control and tool calling. See [MODELS.md](MODELS.md) for the template's origin and what it changes. |
| `--reasoning` / `--reasoning-effort` | `on` / `low` | The model's own default is the highest effort tier and it will over-think trivial prompts. `low` keeps reasoning available without spending 70–85% of generated tokens in the thinking block. Note that reasoning shares the output budget with the answer: with `high`, a 3,000-token budget produced **zero** answer tokens (finish reason `length`). If you raise effort, raise `max_tokens` too. |
| `--temp` / `--top-k` / `--top-p` | `0.7` / `20` / `0.8` | Production sampling. A/B tuning was done at `temp=0`; at 0.7 sampling noise exceeds most of the effects being tuned, so do not tune at production temperature. |
| `--batch-size` / `--ubatch-size` | `1024` / `512` | Prefill batching. Larger ubatch costs VRAM at 128K context; this is the value that keeps the headroom budget. |
| `--threads` / `--threads-batch` | `8` / `8` | Host-side thread count for the CPU parts (tokenization, sampling, copying). |

### 1.3 Environment variables

| Variable | Value | Why |
|---|---|---|
| `GGML_MMVQ_MAX` | `4` | Width threshold for the Turing MMVQ→MMQ route (see the patch). It **must be smaller than `n_max + 1`**, otherwise verification batches never exceed it and the patch becomes a silent no-op. Measured optimum for this model: 4 (`6` → −3.9%, `2` → −9.0%). Reverting to official behaviour: set it `>= n_max + 1` (e.g. `8`). |
| `GGML_MMVQ_ALL` | `1` | Extends the threshold to every quant type MMQ supports instead of `IQ4_XS` only. **Required for this weight set**: the Q2-LynnStyle GGUF is 268 × `IQ3_S` + 88 × `IQ4_XS`, and `IQ4_XS` alone as the routed type measured **−9%**. Conversely, do **not** enable it for an `IQ4_XS`-dominated weight set, where it also loses ~9%. This switch is per weight set, not a global win — inspect the GGUF's tensor types before deciding. |

Both variables are read **once**, at process start (they are cached in function-local statics), so they must be in the environment of the server process. Setting them after launch does nothing.

### 1.4 Measured results (mode A)

RTX 2080 Ti 22 GB (`sm_75`), code prompt, `temp=0`:

| Metric | Value |
|---|---|
| Short-context decode | 64.7 tok/s |
| Decode at 125K context | 30.8 tok/s |
| Prefill | 361–380 tok/s |
| VRAM used | 21,134–21,633 MiB (headroom 895–1,394 MiB) |
| Draft acceptance (DFlash2 n6) | 0.84 |

Turing routing patch, same weights and parameters, only `GGML_MMVQ_MAX` varied:
**+48.9%** against the engine's own stock behaviour (37.2 → 55.5 tok/s) and
**+19.9%** against the previous launcher (46.2 → 55.5 tok/s); on a real MATLAB
Kalman workload 35.72 → 44.87 tok/s (+25.6%). Avoided cost of a single MTP
draft pass is what `ngram-mod` buys back on repeated context.

---

## 2. Mode B — KVMem (256K logical context)

### 2.1 Command line

```text
llama-kvmem-server.exe ^
  --model <Q2-LynnStyle.gguf> ^
  --alias qwen3.8-local ^
  --host 127.0.0.1 --port 8080 ^
  -c 262144 -n 16384 -ngl 99 ^
  --kvmem --kvmem-method retrieval --kvmem-budget 96256 ^
  --kvmem-gen-reserve 16384 --kvmem-block-tokens 128 --kv-dtype q8_0 ^
  --spec-type draft-dflash,ngram-mod ^
  --spec-draft-model <dflash2-qwen38-27b-Q4_K_M.gguf> ^
  --spec-draft-n-max 6 --spec-kv-dtype f16 ^
  --mmproj <mmproj-Qwen3.8-27B-Q4_K_M.gguf> --no-mmproj-offload ^
  --chat-template-file <chat_template.jinja> ^
  --reasoning-effort low --enable-thinking ^
  --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0.05 ^
  -b 1024 -ub 512 --threads 8 --threads-batch 8
```

Environment of the server process:

```text
KVMEM_LAZY_DECODE_MEAN=1
KVMEM_RESUME_INTERVAL=2048
GGML_MMVQ_MAX=4
GGML_MMVQ_ALL=1
```

### 2.2 What each value does

| Flag | Value | Why this value |
|---|---|---|
| `-c` | `262144` | Logical context. This is the number clients see; only part of it is physically resident (below). |
| `-n` | `16384` | Generation reserve — also `--kvmem-gen-reserve` below. **One generation cannot exceed this**, thinking included. If you raise it you must take the space out of `--kvmem-budget`. |
| `--kvmem-method` | `retrieval` | Blocks beyond the resident budget are retrieved instead of kept. |
| `--kvmem-budget` | `96256` | Target-KV resident budget in tokens. With the 16,384-token generation reserve that is a **112,640-token physical working set** ≈ 3.65 GiB. |
| `--kvmem-block-tokens` | `128` | Retrieval block granularity. |
| `--kv-dtype` | `q8_0` | KV type in the KVMem pool. |
| `--spec-type` / `--spec-draft-model` / `--spec-draft-n-max` | as in mode A | In KVMem the DFlash sidecar has to be wired in through the integration patch; `draft-mtp` is not an option here because this Q2 build carries no welded `nextn` head. |
| `--spec-kv-dtype` | `f16` | The DFlash drafter keeps a **plain, non-paged KV cache** (the factory returns null for `LLM_ARCH_DFLASH`). Reason: the drafter writes KV at the target's *physical* positions, which KVMem reassigns on every retrieval, so paging the draft independently would desync it. Its cache therefore allocates the target's **logical** `n_ctx`: `n_ctx × 10.6 KiB` — 2.6 GiB at 262,144, 1.3 GiB at 131,072. This is the main reason the 256K mode needs headroom arithmetic of its own. |
| `--no-mmproj-offload` | — | Same reasoning as mode A; note that the KVMem server does not take `--mmproj-device`. |
| `--chat-template-file` | `chat_template.jinja` | The KVMem server path uses the template file directly; `--jinja` is not passed. |
| `--enable-thinking` + `--reasoning-effort low` | — | Keeping reasoning on but at the lowest tier; see the mode A row on the output budget. |
| `-b` / `-ub`, `--threads` | `1024` / `512`, `8` | As in mode A. |

### 2.3 Environment variables

| Variable | Value | Why |
|---|---|---|
| `KVMEM_LAZY_DECODE_MEAN` | `1` | Lazy block-mean decode: block means are computed when a block is actually read rather than for every block up front. |
| `KVMEM_RESUME_INTERVAL` | `2048` | Extra recurrent checkpoints during long prefill. The engine also keeps one checkpoint at the completed prefill boundary, so a request that is interrupted (client interjects) resumes from that boundary instead of cold-loading the whole prompt. |
| `GGML_MMVQ_MAX` / `GGML_MMVQ_ALL` | `4` / `1` | Same routing patch, same per-weight-set caveat. KVMem's speculative verification batches are the width-D case the patch exists for. |
| `KVMEM_TRACE` | unset by default | Per-verify and per-block logging is opt-in; leaving it off keeps the summary timing lines only. |

### 2.4 Known limits of mode B

- One generation cannot exceed `--kvmem-gen-reserve` (including thinking).
- Speculative rollback runs in host-checkpoint mode (`kparams.mtp_state = 0`): GDN replay requires `n_rs_seq <= 5` and the draft depth here is 6.
- Retrieval is not mathematically identical to keeping all 256K KV positions resident.
- The drafter's logical-size KV cache scales with `-c`, so raising the logical context costs VRAM twice (target pool + draft cache).

Measured results for this mode are in [BENCHMARKS.md](BENCHMARKS.md).

---

## 3. VRAM budget

Measured on the 22 GB card, not estimated:

| Item | Mode A (128K) | Mode B (256K logical) |
|---|---|---|
| Target weights | 12.11 GiB | 12.11 GiB |
| Draft weights | 1.06 GiB | 1.06 GiB |
| Target KV | `q8_0/q8_0` at 131,072 | 112,640-token pool ≈ 3.65 GiB |
| Draft KV | small, `f16` | 262,144 × 10.6 KiB ≈ 2.60 GiB |
| Free headroom to keep | **≥ 0.8 GiB** | **≥ 0.8 GiB** |

### Why 800 MiB, and why it is a hard floor

When free VRAM drops below roughly 700 MiB the CUDA caching allocator stops
reusing cached blocks and falls back to repeated `cudaMalloc`/`cudaFree` (each
synchronises the device), and Windows WDDM starts paging VRAM to host RAM.
Measured collapse: context 204,800 with `q8_0/q4_0` KV → 677 MiB free → prefill
degraded from 375 tok/s to 93 tok/s, with the GPU at 100% utilisation but only
176 W drawn (TDP 250 W). Keep ≥ 800 MiB. After any context/quant change, re-read
the headroom from `nvidia-smi` or the `CUDA0 model buffer size` log line before
trusting the configuration.

---

## 4. Reproduction checklist

These are the things that differ from a stock llama.cpp install, in the order
people usually trip over them:

1. **The routing patch is not optional for the published speeds.** Without it, Turing
   verification batches (width = draft depth + 1) go to MMVQ, which re-decodes the
   weights per column — the dominant loss. Both engines here are built with it.
2. **`GGML_MMVQ_ALL` must match the weight set.** `1` for this IQ3_S-heavy Q2 build,
   `0` for `IQ4_XS`-dominated builds. Getting this backwards costs ~9%.
3. **`GGML_MMVQ_MAX` must be below the verification width** (`n_max + 1`), or the patch
   silently stops firing.
4. **Set the environment variables before launch**, in the server process's
   environment. They are read once, into function-local statics.
5. **`--no-mmproj-offload` or ~1.5 GiB disappears** into the projector.
6. **Keep ≥ 800 MiB free.** This is the difference between 375 tok/s and 93 tok/s
   prefill, and it is not visible until you measure.
7. **Flash attention must be built with all quant types** (`-DGGML_CUDA_FA_ALL_QUANTS=ON`)
   for `q8_0`/`q8_0` KV.
8. **Measure at 60 Hz.** With the desktop at 2560×1440 @ 240 Hz the compositor costs
   roughly 30% of both prefill and decode. Benchmarks taken at 240 Hz are not comparable.
9. **Do not measure speculative decoding by repeating one prompt.** The n-gram lookup
   table survives across requests, so from the second request onward the model matches
   its own previous output and the number is inflated (a 3× inflation was measured and
   the resulting table was retracted). Use independent cold prompts, or reset the server.
10. **n6 and the KV choice belong to this scheme, not to the model.** Changing the
    drafter or the weight set invalidates both; retune.
11. **Chat template.** Both modes are launched with an explicit template, because the
    template is what implements `reasoning_effort`. Without it you get the model's
    default (highest) reasoning effort. See [MODELS.md](MODELS.md).

---

## 5. Not included here

- Model weights and binaries — see [MODELS.md](MODELS.md) for exactly what to download.
- The KVMem engine source, which upstream has not licensed; see [ENGINE_NOTES.md](ENGINE_NOTES.md)
  for the integration checklist and the exact revisions.
- Any client-side reasoning gate/proxy: it sits in front of port 8080 and is not part of
  these launch parameters.
