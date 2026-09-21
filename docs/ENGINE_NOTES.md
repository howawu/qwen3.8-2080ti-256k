# Engine integration notes

This repository publishes the deployment recipe, launchers and measurements. It does **not** redistribute the KVMem engine source because the upstream outer repository currently has no declared license.

## Mode B (KVMem, 256K logical)

Exact local baseline:

- KVMem outer tree: `fd72c5947130beb3aafe867a3364ee72424a99b3`
- llama.cpp submodule: `16378d93f94012d4228c8c7683adce3f286aee5d`
- CUDA architecture: `75-real`
- CUDA toolkit used locally: 13.4

The local engine additionally contains:

1. DFlash sidecar support combined with `ngram-mod`.
2. A plain logical KV cache for the DFlash drafter.
3. Multimodal requests bypass speculative decoding and restore it for following text requests.
4. A cross-request generation-start checkpoint (`mm_anchor`) that prevents a valid LCP from being discarded.
5. Turing MMVQ→MMQ routing for wider speculative verification batches.
6. KVMem resident fast path, lazy block-mean decode and output-boundary rollback fixes.

The launcher in this repository expects a binary that implements these flags. Until upstream licensing is clarified, use the upstream project as the source of the engine and treat the items above as an integration checklist rather than a redistributable fork.

Upstream: <https://github.com/kvmem/kvmem-llama.cpp>
llama.cpp: <https://github.com/ggml-org/llama.cpp>

## Mode A (upstream llama.cpp + DFlash2, 128K)

Mode A is stock llama.cpp at commit `16378d93f94012d4228c8c7683adce3f286aee5d` plus **one** changed file,
published here as [`patches/turing-mmvq-mmq-routing.diff`](../patches/turing-mmvq-mmq-routing.diff)
(`ggml/src/ggml-cuda/mmvq.cu`, 42 added lines).

What it changes: `ggml_cuda_should_use_mmvq()` has per-quant tuning tables for CDNA and for newer NVIDIA
architectures, but on Turing every quant type falls through to `MMVQ_MAX_BATCH_SIZE`. Speculative verification
runs at width `draft_depth + 1`, which lands in the hand-off region: MMVQ re-decodes the weights once per column,
so at that width it loses badly to MMQ (int8 tensor cores, weights staged into shared memory once). The patch adds
a Turing branch with a threshold read from `GGML_MMVQ_MAX`, optionally extended to every MMQ-supported quant type
by `GGML_MMVQ_ALL` — so one build can be A/B tested against both behaviours without recompiling.

Measured effect (RTX 2080 Ti 22 GB, same weights and parameters, only `GGML_MMVQ_MAX` varied): **+48.9%** versus
the same build's stock behaviour (37.2 → 55.5 tok/s) and **+19.9%** versus the previous launcher
(46.2 → 55.5 tok/s). Both switches are per weight set — see [LAUNCH_PARAMS.md](LAUNCH_PARAMS.md) §1.3 before
copying the values.

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

`GGML_CUDA_FA_ALL_QUANTS=ON` is required for `q8_0`/`q8_0` KV with flash attention; the default flash-attention
quant set does not include them. `75-real` avoids emitting PTX the card would have to JIT.

Known model limit, unrelated to the engine: beyond roughly 130K tokens this model is reported to emit EOS early
([llama.cpp #27756](https://github.com/ggml-org/llama.cpp/issues/27756)), which is why mode A stops at 128K and
the 256K mode needs KVMem rather than a larger `-c`.
