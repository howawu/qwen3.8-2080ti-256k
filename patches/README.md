# Published patches

Three patches, three purposes. Each is a diff against **public upstream code**; the upstream
sources themselves are not redistributed here — clone them as shown below and replay.

| Patch | Base commit | Files | Purpose |
|---|---|---:|---|
| `turing-mmvq-mmq-routing.diff` | llama.cpp `16378d93f94012d4228c8c7683adce3f286aee5d` | 1 | Turing MMVQ→MMQ routing for speculative verification batches (needed by mode A, and by mode B's engine too) |
| `llama-kvmem-current.patch` | llama.cpp `16378d93f94012d4228c8c7683adce3f286aee5d` (the submodule of the KVMem tree) | 40 | KVMem integration on the llama.cpp side: DFlash sidecar drafter plus `ngram-mod`, plain logical KV cache for the drafter, multimodal speculative bypass, generation-start checkpoint for cross-request prefix reuse, output-slot sizing across all speculative providers, FP32 GDN record/fold |
| `kvmem-outer-local-changes.patch` | kvmem-llama.cpp `1734a2809bb0422da842d03a4734771ad9439ade` | 10 | KVMem-side wiring: `kvmem-spec` DFlash/ngram options and draft-context plumbing, lazy block-mean decode, resident fast path, server flag parsing and validation, build-script test targets |

## What was verified before publishing

Both KVMem patches were replayed onto a **pristine** tree at their pinned base
(`git archive <pin> | tar -x`, then `git apply --check`), and the resulting files were compared
byte-for-byte against the tree the published measurements were taken on:

- `llama-kvmem-current.patch` → 40/40 files identical, 0 differing, 0 missing.
- `kvmem-outer-local-changes.patch` → 10/10 files identical, 0 differing.

`turing-mmvq-mmq-routing.diff` is the local diff of one file (`ggml/src/ggml-cuda/mmvq.cu`) in a
tree that is otherwise unmodified upstream `16378d9`.

## Replay

```bash
git clone https://github.com/kvmem/kvmem-llama.cpp
KVMEM_DIR=$PWD/kvmem-llama.cpp scripts/apply-engine-patches.sh
```

`scripts/apply-engine-patches.sh` checks out both pinned commits, initialises the submodule,
applies the patches (skipping any that is already applied) and prints the build command. It is
safe to re-run.

The engine tree's own Windows build script also knows about `llama-kvmem-current.patch` and will
apply it if you did not (`-SkipPatch` opts out). After the patches are in place:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <kvmem>\scripts\windows\build.ps1 `
  -SourceDir <kvmem> -BuildDir <kvmem>\build-win -CudaArchitectures 75-real -Jobs 6
```

## Why these are published as patches

The KVMem outer repository currently declares no license. This repository therefore publishes
neither its source nor a fork of it — only the diffs needed to reproduce the deployment, applied
onto the upstream tree you obtain yourself. Treat them as interoperability patches and keep the
upstream terms in mind when redistributing anything derived from them. See
[THIRD_PARTY.md](../THIRD_PARTY.md).

## Not included

- The local, hardware-specific tuning notes (power-limit handling, per-machine paths).
- Model weights, GGUFs and binaries of any kind.
