# Mode A launcher -- upstream llama.cpp + DFlash2, 128K context, port 8080.
#
#   engine  llama-server.exe built from upstream llama.cpp 16378d9 with the
#           Turing MMVQ->MMQ routing patch (patches/turing-mmvq-mmq-routing.diff).
#           Without the patch the speculative verification batches fall back to
#           MMVQ and the published speeds are not reachable; see
#           docs/LAUNCH_PARAMS.md section 4.
#   model   Q2-LynnStyle target GGUF (text-only, no welded MTP head)
#   draft   DFlash2 Q4_K_M block-diffusion drafter, speculative depth 6
#   spec    --spec-type draft-dflash,ngram-mod
#           ngram runs FIRST (priority is hardcoded in the engine: ngram* >
#           draft*), fires only on genuinely repeated content and abstains
#           otherwise, so on free-flowing text this is identical to
#           draft-dflash alone. Revert by setting LlamaSpecType = 'draft-dflash'.
#   KV      q8_0 / q8_0 at 128K. 128K is the largest verified context for this
#           model; beyond ~130K tokens it is reported to emit EOS early
#           (llama.cpp #27756). Use scripts/start-kvmem.ps1 for 256K.
#
# This script owns llama-server.exe only. Mode B (KVMem) is a different binary
# on the same port; the two are mutually exclusive on a 22 GB card.
#
# VRAM headroom is load-bearing: below roughly 700 MiB free the CUDA caching
# allocator starts cudaMalloc/cudaFree churn and Windows WDDM pages VRAM to host
# RAM (measured: prefill 375 -> 93 t/s). Keep >= 800 MiB free.
#
# NOTE: keep this file pure ASCII -- Windows PowerShell 5.1 decodes BOM-less
#       .ps1 files using the ANSI code page, which would corrupt non-ASCII text.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot 'config.ps1'
if (-not (Test-Path $configPath)) {
    Write-Host 'Missing config.ps1. Copy config.example.ps1 to config.ps1 first.' -ForegroundColor Red
    exit 1
}
. $configPath

# ---- defaults for anything config.ps1 leaves undefined ----
if (-not $LlamaContext)    { $LlamaContext = 131072 }
if (-not $LlamaKVType)     { $LlamaKVType = 'q8_0' }
if (-not $LlamaSpecType)   { $LlamaSpecType = 'draft-dflash,ngram-mod' }
if (-not $LlamaDraftDepth) { $LlamaDraftDepth = 6 }
if (-not $LlamaBatchSize)  { $LlamaBatchSize = 1024 }
if (-not $LlamaUBatchSize) { $LlamaUBatchSize = 512 }
if (-not $MmvqMax)         { $MmvqMax = 4 }
if (-not $MmvqAll)         { $MmvqAll = 1 }
if (-not $Port)            { $Port = 8080 }
if (-not $Threads)         { $Threads = 8 }
if (-not $LogDir)          { $LogDir = Join-Path $repoRoot 'logs' }

$required = @($LlamaServer, $TargetModel, $DraftModel, $ChatTemplate)
foreach ($path in $required) {
    if (-not $path -or -not (Test-Path $path)) {
        Write-Host "Missing required file: $path" -ForegroundColor Red
        Write-Host 'Run scripts/check-config.ps1 for the full list, and see docs/MODELS.md.' -ForegroundColor Yellow
        exit 1
    }
}

# Stop an instance of THIS server only, never somebody else's process.
$serverFullPath = (Resolve-Path $LlamaServer).Path
$mine = Get-CimInstance Win32_Process -Filter "Name = 'llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $serverFullPath }
if ($mine) {
    foreach ($process in $mine) { Stop-Process -Id $process.ProcessId -Force }
    Write-Host 'Stopped this configured llama-server.'
    exit 0
}

# Mode B shares the port. Warn rather than killing whatever holds it.
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    $owner = (Get-Process -Id $listener[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
    Write-Host "Port $Port is already in use by '$owner'. Stop it before starting mode A." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $LogDir "server-$timestamp.out.log"
$stderr = Join-Path $LogDir "server-$timestamp.err.log"

# Read once at process start by the patched ggml_cuda_should_use_mmvq():
#   GGML_MMVQ_MAX  routing threshold; must stay below the verification width
#                  (draft depth + 1) or the patch silently stops firing.
#   GGML_MMVQ_ALL  extend the threshold to every quant type MMQ supports.
#                  Required for this IQ3_S-heavy weight set; costs ~9% on an
#                  IQ4_XS-dominated one.
$env:GGML_MMVQ_MAX = "$MmvqMax"
$env:GGML_MMVQ_ALL = "$MmvqAll"

function Quote-WindowsArg([string]$value) {
    return '"' + $value.Replace('"', '\"') + '"'
}

# The vision projector is kept in HOST memory: --mmproj-offload defaults to
# enabled and overrides --mmproj-device none, and pushing the 522 MB projector
# onto the GPU costs ~1.5 GiB (measured 21908 vs 20375 MiB used). Image input
# still works without the offload.
$mmprojArgs = @()
if ($MmprojModel -and (Test-Path $MmprojModel)) {
    $mmprojArgs = @('--mmproj', (Quote-WindowsArg $MmprojModel), '--mmproj-device', 'none', '--no-mmproj-offload')
}

$arguments = @(
    '--model', (Quote-WindowsArg $TargetModel),
    '--alias', 'qwen3.8-local',
    '--host', '127.0.0.1',
    '--port', "$Port",
    '--ctx-size', "$LlamaContext",
    '--parallel', '1',
    '--n-gpu-layers', 'all',
    '--fit', 'off',
    '--flash-attn', 'on',
    '--cache-type-k', $LlamaKVType,
    '--cache-type-v', $LlamaKVType,
    '--spec-type', $LlamaSpecType,
    '--spec-draft-model', (Quote-WindowsArg $DraftModel),
    '--spec-draft-n-max', "$LlamaDraftDepth",
    '--spec-draft-type-k', 'f16',
    '--spec-draft-type-v', 'f16',
    '--jinja',
    '--chat-template-file', (Quote-WindowsArg $ChatTemplate),
    '--reasoning', 'on',
    '--reasoning-effort', 'low',
    '--temp', '0.7',
    '--top-k', '20',
    '--top-p', '0.8',
    '--batch-size', "$LlamaBatchSize",
    '--ubatch-size', "$LlamaUBatchSize",
    '--threads', "$Threads",
    '--threads-batch', "$Threads"
) + $mmprojArgs

Write-Host "Starting mode A: llama.cpp + DFlash2 (ctx=$LlamaContext KV=$LlamaKVType spec=$LlamaSpecType depth=$LlamaDraftDepth MMVQ_MAX=$MmvqMax ALL=$MmvqAll)" -ForegroundColor Cyan
Start-Process $LlamaServer -ArgumentList ($arguments -join ' ') -WindowStyle Hidden `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Write-Host "API:  http://127.0.0.1:$Port" -ForegroundColor Green
Write-Host "Logs: $stderr" -ForegroundColor Green
