# One-command bootstrap for the mode B (KVMem, 256K) engine on Windows.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-engine.ps1 -Build
#
# It clones the upstream KVMem tree if needed, checks out the exact commits the
# published measurements were taken on, replays the two patches in patches/ and
# (with -Build) builds llama-kvmem-server.exe for Turing.
#
# Safe to re-run: already applied patches are detected and skipped, steps that
# are already in place are reported instead of repeated.
#
# NOTE: keep this file pure ASCII -- Windows PowerShell 5.1 decodes BOM-less
#       .ps1 files using the ANSI code page, which would corrupt non-ASCII text.

[CmdletBinding()]
param(
    [string]$KvmemDir,
    [switch]$Build,
    [string]$BuildDir,
    [string]$CudaPath = $env:CUDA_PATH,
    [string]$CudaArchitectures = '75-real',
    [int]$Jobs = 6
)

$ErrorActionPreference = 'Stop'

$KV_LLAMA_PIN = '16378d93f94012d4228c8c7683adce3f286aee5d'
$KV_OUTER_PIN = '1734a2809bb0422da842d03a4734771ad9439ade'
$UPSTREAM = 'https://github.com/kvmem/kvmem-llama.cpp'

$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $KvmemDir) { $KvmemDir = Join-Path $repoRoot 'kvmem-llama.cpp' }
if (-not $BuildDir) { $BuildDir = Join-Path $KvmemDir 'build-win' }
$patchOuter = Join-Path $repoRoot 'patches\kvmem-outer-local-changes.patch'
$patchLlama = Join-Path $repoRoot 'patches\llama-kvmem-current.patch'

foreach ($p in @($patchOuter, $patchLlama)) {
    if (-not (Test-Path $p)) { throw "missing patch file: $p" }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required' }

function Invoke-Git {
    param([string]$Dir, [string[]]$GitArgs)
    & git -C $Dir @GitArgs
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed (exit $LASTEXITCODE)" }
}

# git's own messages are informational here (detached HEAD, already applied).
$gitQuiet = @('-c', 'advice.detachedHead=false')

Write-Host '[1/4] KVMem checkout' -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $KvmemDir '.git'))) {
    Write-Host "      cloning $UPSTREAM"
    Invoke-Git (Split-Path $KvmemDir -Parent) @('clone', $UPSTREAM, (Split-Path $KvmemDir -Leaf))
} else {
    Write-Host "      reusing $KvmemDir"
}
& git -C $KvmemDir cat-file -e "$KV_OUTER_PIN^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { throw "commit $KV_OUTER_PIN is missing; run 'git -C $KvmemDir fetch' and retry" }
Invoke-Git $KvmemDir (@($gitQuiet) + @('checkout', '--quiet', $KV_OUTER_PIN))

& git -C $KvmemDir apply --reverse --check $patchOuter 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host '      outer patch already applied'
} else {
    Invoke-Git $KvmemDir (@('apply', '--check', $patchOuter))
    Invoke-Git $KvmemDir (@('apply', $patchOuter))
    Write-Host '      applied kvmem-outer-local-changes.patch (10 files)'
}

Write-Host '[2/4] llama.cpp submodule' -ForegroundColor Cyan
Invoke-Git $KvmemDir @('submodule', 'update', '--init', 'llama.cpp')
$llamaDir = Join-Path $KvmemDir 'llama.cpp'
Invoke-Git $llamaDir (@($gitQuiet) + @('checkout', '--quiet', $KV_LLAMA_PIN))

Write-Host '[3/4] llama.cpp patch' -ForegroundColor Cyan
& git -C $llamaDir apply --reverse --check $patchLlama 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host '      llama.cpp patch already applied'
} else {
    Invoke-Git $llamaDir (@('apply', '--check', $patchLlama))
    Invoke-Git $llamaDir (@('apply', $patchLlama))
    Write-Host '      applied llama-kvmem-current.patch (40 files)'
}

Write-Host '[4/4] done' -ForegroundColor Green
if ($Build) {
    $buildScript = Join-Path $KvmemDir 'scripts\windows\build.ps1'
    if (-not (Test-Path $buildScript)) { throw "build script not found: $buildScript" }
    Write-Host "      building into $BuildDir (CUDA $CudaArchitectures, $Jobs jobs)"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript `
        -SourceDir $KvmemDir -BuildDir $BuildDir -CudaPath $CudaPath `
        -CudaArchitectures $CudaArchitectures -Jobs $Jobs
    if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }
    Write-Host "      binary: $BuildDir\bin\llama-kvmem-server.exe" -ForegroundColor Green
    Write-Host '      point config.ps1 at it ($KVMemServer) and run scripts\start-kvmem.ps1'
} else {
    Write-Host "      build with: powershell -File `"$KvmemDir\scripts\windows\build.ps1`" -SourceDir `"$KvmemDir`" -BuildDir `"$BuildDir`" -CudaArchitectures $CudaArchitectures -Jobs $Jobs"
}
