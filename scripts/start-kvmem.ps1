$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot 'config.ps1'
if (-not (Test-Path $configPath)) {
    Write-Host 'Missing config.ps1. Copy config.example.ps1 to config.ps1 first.' -ForegroundColor Red
    exit 1
}
. $configPath

$required = @($KVMemServer, $TargetModel, $DraftModel, $ChatTemplate)
foreach ($path in $required) {
    if (-not (Test-Path $path)) {
        Write-Host "Missing required file: $path" -ForegroundColor Red
        exit 1
    }
}

$serverFullPath = (Resolve-Path $KVMemServer).Path
$mine = Get-CimInstance Win32_Process -Filter "Name = 'llama-kvmem-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $serverFullPath }
if ($mine) {
    foreach ($process in $mine) { Stop-Process -Id $process.ProcessId -Force }
    Write-Host 'Stopped this configured llama-kvmem-server.'
    exit 0
}

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    $owner = (Get-Process -Id $listener[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
    Write-Host "Port $Port is already in use by '$owner'. Stop it before starting KVMem." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $LogDir "kvmem-$timestamp.out.log"
$stderr = Join-Path $LogDir "kvmem-$timestamp.err.log"

$env:KVMEM_LAZY_DECODE_MEAN = '1'
$env:GGML_MMVQ_MAX = '4'
$env:GGML_MMVQ_ALL = '1'

function Quote-WindowsArg([string]$value) {
    return '"' + $value.Replace('"', '\"') + '"'
}

$arguments = @(
    '--model', (Quote-WindowsArg $TargetModel),
    '--alias', 'qwen3.8-local',
    '--host', '127.0.0.1',
    '--port', "$Port",
    '-c', "$ContextSize",
    '-n', "$GenerationReserve",
    '-ngl', '99',
    '--kvmem',
    '--kvmem-method', 'retrieval',
    '--kvmem-budget', "$KVMemBudget",
    '--kvmem-gen-reserve', "$GenerationReserve",
    '--kvmem-block-tokens', "$KVMemBlockTokens",
    '--kv-dtype', $KVDtype,
    '--spec-type', $SpecType,
    '--spec-draft-model', (Quote-WindowsArg $DraftModel),
    '--spec-draft-n-max', "$DraftDepth",
    '--spec-kv-dtype', 'f16',
    '--chat-template-file', (Quote-WindowsArg $ChatTemplate),
    '--reasoning-effort', 'low',
    '--enable-thinking',
    '--temp', '0.7',
    '--top-p', '0.8',
    '--top-k', '20',
    '--min-p', '0.05',
    '-b', "$BatchSize",
    '-ub', "$UBatchSize",
    '--threads', "$Threads",
    '--threads-batch', "$Threads"
)

if ($MmprojModel -and (Test-Path $MmprojModel)) {
    $arguments += @('--mmproj', (Quote-WindowsArg $MmprojModel), '--no-mmproj-offload')
}

Write-Host "Starting 256K KVMem service on http://127.0.0.1:$Port" -ForegroundColor Cyan
Start-Process $KVMemServer -ArgumentList ($arguments -join ' ') -WindowStyle Hidden `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Write-Host "Logs: $stderr" -ForegroundColor Green
