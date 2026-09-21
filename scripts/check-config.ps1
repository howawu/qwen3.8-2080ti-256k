$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot 'config.ps1'
if (-not (Test-Path $configPath)) { throw 'Copy config.example.ps1 to config.ps1 first.' }
. $configPath

function Show-Path([string]$label, [string]$path, [bool]$optional) {
    if ($path -and (Test-Path $path)) {
        Write-Host ("{0,-22} {1,-8} {2}" -f $label, 'OK', $path)
    } elseif ($optional) {
        Write-Host ("{0,-22} {1,-8} {2}" -f $label, 'absent', '(optional)')
    } else {
        Write-Host ("{0,-22} {1,-8} {2}" -f $label, 'MISSING', $path) -ForegroundColor Red
    }
}

Write-Host '--- shared files ---'
Show-Path 'target_model'  $TargetModel  $false
Show-Path 'draft_model'   $DraftModel   $false
Show-Path 'mmproj'        $MmprojModel  $true
Show-Path 'chat_template' $ChatTemplate $false

Write-Host ''
Write-Host '--- mode A: llama.cpp + DFlash2 (128K) ---'
Show-Path 'llama-server'  $LlamaServer  $false
if ($LlamaContext) {
    $kvType = if ($LlamaKVType) { $LlamaKVType } else { 'q8_0' }
    Write-Host ("context {0} tokens, KV {1}/{1}, spec {2} depth {3}" -f $LlamaContext, $kvType,
        $(if ($LlamaSpecType) { $LlamaSpecType } else { 'draft-dflash,ngram-mod' }),
        $(if ($LlamaDraftDepth) { $LlamaDraftDepth } else { 6 }))
    $mmvqMax = if ($MmvqMax) { $MmvqMax } else { 4 }
    $mmvqAll = if ($MmvqAll) { $MmvqAll } else { 1 }
    Write-Host "MMVQ routing: GGML_MMVQ_MAX=$mmvqMax GGML_MMVQ_ALL=$mmvqAll"
    $width = [int]$(if ($LlamaDraftDepth) { $LlamaDraftDepth } else { 6 }) + 1
    if ([int]$mmvqMax -ge $width) {
        Write-Host "  WARNING: MMVQ_MAX ($mmvqMax) >= verification width ($width): the routing patch will not fire." -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '--- mode B: KVMem (256K logical) ---'
Show-Path 'llama-kvmem-server' $KVMemServer $false
$budget  = if ($KVMemBudget) { [int64]$KVMemBudget } else { 96256 }
$reserve = if ($GenerationReserve) { [int64]$GenerationReserve } else { 16384 }
$logical = if ($ContextSize) { [int64]$ContextSize } else { 262144 }
Write-Host ("logical context    : {0} tokens" -f $logical)
Write-Host ("GPU KV working set : {0} tokens (budget {1} + generation reserve {2})" -f ($budget + $reserve), $budget, $reserve)
$draftDepth = if ($DraftDepth) { $DraftDepth } else { 6 }
Write-Host ("speculation        : {0}, DFlash depth {1}" -f $(if ($SpecType) { $SpecType } else { 'draft-dflash,ngram-mod' }), $draftDepth)

Write-Host ''
Write-Host 'Both modes bind the same port and are mutually exclusive; run one at a time.'
Write-Host 'Every value above is explained in docs/LAUNCH_PARAMS.md.'
