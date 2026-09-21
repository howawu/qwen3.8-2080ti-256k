# Engine integration notes

This repository publishes a deployment recipe, launchers, measurements **and the exact diffs
needed to rebuild both engines**. It does not redistribute third-party source trees: you obtain
the upstreams yourself and replay the patches published here.

## Mode B (KVMem, 256K logical)

Upstream sources (both public):

- KVMem outer tree: <https://github.com/kvmem/kvmem-llama.cpp>, pinned at `1734a2809bb0422da842d03a4734771ad9439ade`
- llama.cpp submodule: `16378d93f94012d4228c8c7683adce3f286aee5d` (upstream `master`)
- CUDA architecture: `75-real`; CUDA toolkit used locally: 13.4

Published patches (see [`patches/README.md`](../patches/README.md) for bases, file counts and the
verification performed before publication):

| Patch | Side | Files |
|---|---|---:|
| `patches/kvmem-outer-local-changes.patch` | KVMem outer tree | 10 |
| `patches/llama-kvmem-current.patch` | llama.cpp submodule | 40 |

Replay:

```bash
git clone https://github.com/kvmem/kvmem-llama.cpp
KVMEM_DIR=$PWD/kvmem-llama.cpp scripts/apply-engine-patches.sh          # Linux, macOS, git-bash
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-engine.ps1 -Build   # Windows, one command
```

What the patches add over upstream:

1. DFlash sidecar support combined with `ngram-mod`.
2. A plain logical KV cache for the DFlash drafter (the drafter writes KV at the target's physical
   positions, which KVMem reassigns on retrieval, so paging the draft independently would desync it).
3. Multimodal requests bypass speculative decoding and restore it for following text requests.
4. A cross-request generation-start checkpoint (`mm_anchor`) that prevents a valid LCP from being discarded.
5. Turing MMVQ→MMQ routing for wider speculative verification batches (also published standalone as
   `patches/turing-mmvq-mmq-routing.diff`).
6. KVMem resident fast path, lazy block-mean decode and output-boundary rollback fixes.

Upstream licensing: the KVMem outer repository currently declares no license, which is why the
integration is published as diffs against the upstream commits above rather than as a fork, and why
the upstream sources themselves are not bundled here. Keep the upstream terms in mind if you
redistribute anything derived from those patches.

## Mode A (upstream llama.cpp + DFlash2, 128K)

Mode A is stock llama.cpp at commit `16378d93f94012d4228c8c7683adce3f286aee5d` plus **one** changed
file, published here as [`patches/turing-mmvq-mmq-routing.diff`](../patches/turing-mmvq-mmq-routing.diff)
(`ggml/src/ggml-cuda/mmvq.cu`, 42 added lines).

What it changes: `ggml_cuda_should_use_mmvq()` has per-quant tuning tables for CDNA and for newer
NVIDIA architectures, but on Turing every quant type falls through to `MMVQ_MAX_BATCH_SIZE`.
Speculative verification runs at width `draft_depth + 1`, which lands in the hand-off region: MMVQ
re-decodes the weights once per column, so at that width it loses badly to MMQ (int8 tensor cores,
weights staged into shared memory once). The patch adds a Turing branch with a threshold read from
`GGML_MMVQ_MAX`, optionally extended to every MMQ-supported quant type by `GGML_MMVQ_ALL` — so one
build can be A/B tested against both behaviours without recompiling.

Measured effect (RTX 2080 Ti 22 GB, same weights and parameters, only `GGML_MMVQ_MAX` varied):
**+48.9%** versus the same build's stock behaviour (37.2 → 55.5 tok/s) and **+19.9%** versus the
previous launcher (46.2 → 55.5 tok/s). Both switches are per weight set — see
[LAUNCH_PARAMS.md](LAUNCH_PARAMS.md) §1.3 before copying the values.

Build (Windows, MSVC 2022 + CUDA 13.x, Ninja):

```bat
cmake -S llama.cpp -B build -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DGGML_CUDA=ON ^
  -DCMAKE_CUDA_COMPILER="<cuda>/bin/nvcc.exe" ^
  -DCMAKE_CUDA_ARCHITECTURES=75-real ^
  -DGGML_NATIVE=ON ^
  -DGGML_CUDA_FA_ALL_QUANTS=ON ^
  -DLLAMA_CURL=OFF ^
  -DLLAMA_BUILD_TESTS=OFF ^
  -DLLAMA_BUILD_EXAMPLES=ON
cmake --build build -j
```

`GGML_CUDA_FA_ALL_QUANTS=ON` is required for `q8_0`/`q8_0` KV with flash attention; the default
flash-attention quant set does not include them. `75-real` avoids emitting PTX the card would have
to JIT.

Known model limit, unrelated to the engine: beyond roughly 130K tokens this model is reported to emit
EOS early ([llama.cpp #27756](https://github.com/ggml-org/llama.cpp/issues/27756)), which is why mode
A stops at 128K and the 256K mode needs KVMem rather than a larger `-c`.
