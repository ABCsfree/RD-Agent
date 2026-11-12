#!/bin/bash
# RD-Agent launcher for Linux / WSL (validated 2026-11-12, see DEPLOYMENT.md)
#
# Usage:
#   ./run.sh fin_factor     # factor auto-evolution loop
#   ./run.sh fin_quant      # factor + model joint evolution
#   ./run.sh health_check   # verify LLM / embedding / docker / port
#   ./run.sh server_ui      # Web UI (http://localhost:19899/?token=<token>)
#
# This script is designed to be run from the repo root of this fork.
# It exists because RD-Agent assumes a conda-based deployment by default:
#   * CONDA_DEFAULT_ENV  - CondaConf validation requires a non-empty value
#   * conda shim         - CondaConf probes `conda run -n X env` for PATH;
#                          /usr/local/bin/conda (deploy/conda-shim.sh) answers
#                          with this venv's bin dir, so factor code runs on
#                          the venv interpreter (has pandas/tables).
#   * MODEL_COSTEER_ENV_TYPE=docker - run Qlib backtests in Docker instead
#                          of a local conda env (no conda needed at all).
#   * UI_SERVER_AUTH_TOKEN - required by server_ui in newer versions.

set -e

# Resolve repo root from this script's location (repo root when copied as ./run.sh,
# or deploy/ if executed in place).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "deploy" ]; then
    export RDAGENT_DIR="$(dirname "$SCRIPT_DIR")"
else
    export RDAGENT_DIR="$SCRIPT_DIR"
fi

export CONDA_DEFAULT_ENV="${CONDA_DEFAULT_ENV:-rdagent}"
export MODEL_COSTEER_ENV_TYPE="${MODEL_COSTEER_ENV_TYPE:-docker}"
export UI_SERVER_AUTH_TOKEN="${UI_SERVER_AUTH_TOKEN:-change-me-in-dot-env}"
# Optional: Simplified Chinese free-text output from the LLM (also settable in .env)
# export DEFAULT_SYSTEM_PROMPT="You are an AI assistant who helps to answer user's questions. IMPORTANT: Always write all free-text content in Simplified Chinese. Keep code, JSON field names, and variable names in English unchanged."

cd "$RDAGENT_DIR"
exec ".venv/bin/rdagent" "$@"
