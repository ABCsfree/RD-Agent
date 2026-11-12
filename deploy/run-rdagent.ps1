# RD-Agent launcher for native Windows (LIMITED - see notes below)
# Validated 2026-11-12. See DEPLOYMENT.md for the full story.
#
# USAGE:
#   .\deploy\run-rdagent.ps1 health_check     # verify LLM / docker / port  - works
#   .\deploy\run-rdagent.ps1 server_ui        # Web UI                      - works
#   .\deploy\run-rdagent.ps1 fin_factor       # factor loop                 - DOES NOT WORK
#
# IMPORTANT: quant scenarios (fin_factor / fin_quant / fin_model) currently
# CANNOT run on native Windows (CondaConf conda assumption, PATH built with
# ':' separators, symlinks, /bin hardcoding). For those, use WSL2 Ubuntu and
# deploy/run.sh instead. This script remains useful for health_check,
# server_ui and configuration experiments on native Windows.
#
# It fixes three Windows-specific pitfalls before launching rdagent:
#   1. Removes stale (possibly empty) OPENAI_API_KEY / OPENAI_BASE_URL env
#      vars - load_dotenv never overrides existing vars, so they would block
#      the real keys from .env.
#   2. Replaces NO_PROXY - a '[::1]' entry makes litellm fail every request
#      with "Invalid port: ':1]'".
#   3. Forces PYTHONUTF8 - the GBK console cannot render log emoji.

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RdArgs
)

if (-not $RdArgs -or $RdArgs.Count -eq 0) {
    $RdArgs = @("--help")
}

Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:OPENAI_BASE_URL -ErrorAction SilentlyContinue
$env:NO_PROXY = "localhost,127.0.0.1"
$env:PYTHONUTF8 = "1"

Write-Host ">>> launching rdagent $($RdArgs -join ' ')" -ForegroundColor Cyan
& "$PSScriptRoot\..\.venv\Scripts\rdagent.exe" @RdArgs
exit $LASTEXITCODE
