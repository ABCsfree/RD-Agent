@echo off
rem RD-Agent launcher for native Windows (bypasses PowerShell execution policy)
rem LIMITED: quant scenarios do not work on native Windows - use WSL for those.
rem See run-rdagent.ps1 header and DEPLOYMENT.md for details.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-rdagent.ps1" %*
