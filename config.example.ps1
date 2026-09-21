# Copy this file to config.ps1 and edit only the paths.
# Keep model weights outside the repository.

$KVMemServer = 'C:\path\to\llama-kvmem-server.exe'
$TargetModel = 'C:\path\to\Qwen3.8-27B-EfficientThink-Q2.gguf'
$DraftModel  = 'C:\path\to\dflash2-qwen38-27b-Q4_K_M.gguf'
$MmprojModel = 'C:\path\to\mmproj-Qwen3.8-27B-Q4_K_M.gguf' # optional
$ChatTemplate = 'C:\path\to\chat_template.jinja'
$LogDir = "$PSScriptRoot\logs"

$Port = 8080
$ContextSize = 262144
$KVMemBudget = 96256
$GenerationReserve = 16384
$KVMemBlockTokens = 128
$KVDtype = 'q8_0'
$DraftDepth = 6
$SpecType = 'draft-dflash,ngram-mod'
$BatchSize = 1024
$UBatchSize = 512
$Threads = 8
