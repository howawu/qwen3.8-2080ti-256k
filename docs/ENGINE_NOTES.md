# Engine integration notes

This repository publishes the deployment recipe, launcher and measurements. It does **not** redistribute the KVMem engine source because the upstream outer repository currently has no declared license.

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
