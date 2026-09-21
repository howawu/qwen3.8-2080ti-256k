$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot 'config.ps1'
if (-not (Test-Path $configPath)) { throw 'Copy config.example.ps1 to config.ps1 first.' }
. $configPath

$items = [ordered]@{
    server = $KVMemServer
    target_model = $TargetModel
    draft_model = $DraftModel
    mmproj_optional = $MmprojModel
    chat_template = $ChatTemplate
}
foreach ($entry in $items.GetEnumerator()) {
    $status = if ($entry.Value -and (Test-Path $entry.Value)) { 'OK' } else { 'MISSING' }
    Write-Host ("{0,-18} {1,-8} {2}" -f $entry.Key, $status, $entry.Value)
}

$physicalTokens = [int64]$KVMemBudget + [int64]$GenerationReserve
Write-Host "logical context : $ContextSize tokens"
Write-Host "GPU KV working set: $physicalTokens tokens"
Write-Host "speculation      : $SpecType, DFlash depth $DraftDepth"
