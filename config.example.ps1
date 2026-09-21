# Copy this file to config.ps1 and edit the paths (and only the paths, unless you
# are deliberately re-tuning -- docs/LAUNCH_PARAMS.md explains every value).
# Keep model weights outside the repository.

# ---- shared ----
$TargetModel  = 'C:\path\to\Qwen3.8-27B-EfficientThink-SimPO-Q2-LynnStyle.gguf'
$DraftModel   = 'C:\path\to\dflash2-qwen38-27b-Q4_K_M.gguf'
$MmprojModel  = 'C:\path\to\mmproj-Qwen3.8-27B-Q4_K_M.gguf'   # optional; kept in host RAM
$ChatTemplate = 'C:\path\to\chat_template.jinja'              # see docs/MODELS.md
$LogDir       = "$PSScriptRoot\logs"
$Port         = 8080
$Threads      = 8

# ---- mode A: upstream llama.cpp + DFlash2, 128K (scripts/start-llama.ps1) ----
$LlamaServer     = 'C:\path\to\llama-server.exe'
$LlamaContext    = 131072
$LlamaKVType     = 'q8_0'
$LlamaSpecType   = 'draft-dflash,ngram-mod'
$LlamaDraftDepth = 6
$LlamaBatchSize  = 1024
$LlamaUBatchSize = 512
$MmvqMax         = 4   # must stay below the verification width (draft depth + 1)
$MmvqAll         = 1   # required for this IQ3_S-heavy weight set

# ---- mode B: KVMem, 256K logical (scripts/start-kvmem.ps1) ----
$KVMemServer     = 'C:\path\to\llama-kvmem-server.exe'
$ContextSize     = 262144
$KVMemBudget     = 96256
$GenerationReserve = 16384
$KVMemBlockTokens = 128
$KVDtype         = 'q8_0'
$DraftDepth      = 6
$SpecType        = 'draft-dflash,ngram-mod'
$BatchSize       = 1024
$UBatchSize      = 512
