#!/usr/bin/env bash
# Replay the published engine patches onto a fresh KVMem checkout.
#
#   git clone https://github.com/kvmem/kvmem-llama.cpp
#   KVMEM_DIR=$PWD/kvmem-llama.cpp scripts/apply-engine-patches.sh
#
# Safe to re-run: an already applied patch is detected and skipped, and both
# trees are checked out at the exact commits the measurements were taken on.

set -euo pipefail

KV_LLAMA_PIN=16378d93f94012d4228c8c7683adce3f286aee5d
KV_OUTER_PIN=1734a2809bb0422da842d03a4734771ad9439ade

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_OUTER="$REPO_ROOT/patches/kvmem-outer-local-changes.patch"
PATCH_LLAMA="$REPO_ROOT/patches/llama-kvmem-current.patch"
KV_DIR="${KVMEM_DIR:-$REPO_ROOT/kvmem-llama.cpp}"

# Git for Windows is a native binary and cannot open the MSYS-style paths
# (/c/Users/...) that bash hands it. Convert to a mixed path when cygpath is
# available; on Linux/macOS the paths are already native.
to_native() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
NATIVE_KV="$(to_native "$KV_DIR")"
NATIVE_OUTER="$(to_native "$PATCH_OUTER")"
NATIVE_LLAMA="$(to_native "$PATCH_LLAMA")"
NATIVE_SUB="$NATIVE_KV/llama.cpp"

for p in "$PATCH_OUTER" "$PATCH_LLAMA"; do
    [ -f "$p" ] || { echo "missing patch file: $p" >&2; exit 1; }
done

if [ ! -d "$NATIVE_KV/.git" ] && [ ! -f "$NATIVE_KV/.git" ]; then
    echo "KVMem checkout not found at: $NATIVE_KV" >&2
    echo "Clone it first (git clone https://github.com/kvmem/kvmem-llama.cpp) or set KVMEM_DIR." >&2
    exit 1
fi

apply_patch() {
    local dir="$1" patch="$2" label="$3"
    if git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
        echo "      already applied: $label"
        return
    fi
    git -C "$dir" apply --check "$patch"
    git -C "$dir" apply "$patch"
    echo "      applied: $label"
}

echo "[1/4] outer tree -> $KV_OUTER_PIN"
git -C "$NATIVE_KV" cat-file -e "$KV_OUTER_PIN^{commit}" 2>/dev/null || {
    echo "commit $KV_OUTER_PIN not present; run 'git -C $NATIVE_KV fetch' and retry" >&2; exit 1; }
git -C "$NATIVE_KV" checkout --quiet "$KV_OUTER_PIN"
apply_patch "$NATIVE_KV" "$NATIVE_OUTER" "kvmem-outer-local-changes.patch (10 files)"

echo "[2/4] llama.cpp submodule -> $KV_LLAMA_PIN"
git -C "$NATIVE_KV" submodule update --init --recursive llama.cpp
git -C "$NATIVE_SUB" checkout --quiet "$KV_LLAMA_PIN"

echo "[3/4] llama.cpp patch"
apply_patch "$NATIVE_SUB" "$NATIVE_LLAMA" "llama-kvmem-current.patch (40 files)"

echo "[4/4] done. Build with the tree's own script (it detects the applied patch):"
echo "  powershell -NoProfile -ExecutionPolicy Bypass -File \"$KV_DIR/scripts/windows/build.ps1\" \\"
echo "    -SourceDir \"$KV_DIR\" -BuildDir \"$KV_DIR/build-win\" -CudaArchitectures 75-real -Jobs 6"
echo
echo "Mode A can use the same llama.cpp tree: apply patches/turing-mmvq-mmq-routing.diff"
echo "to a separate checkout of $KV_LLAMA_PIN and build llama-server."
