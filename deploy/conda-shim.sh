#!/bin/bash
# Minimal conda shim for RD-Agent on machines WITHOUT real conda (validated 2026-11-12).
# Install: sudo cp deploy/conda-shim.sh /usr/local/bin/conda && sudo chmod +x /usr/local/bin/conda
#
# Why this exists: rdagent/utils/env.py CondaConf._update_bin_path() runs
#   conda run -n <env> --no-capture-output env | grep '^PATH='
# to find the python bin dir for local (non-Docker) component execution.
# Without conda installed the probe fails (bin_path stays empty) and local
# execution may resolve 'python' to the wrong interpreter.
#
# Only one invocation pattern is supported (the PATH probe above). It answers
# with the venv bin directory of the RD-Agent checkout. Adjust RDAGENT_DIR
# if you cloned the repo somewhere else.

RDAGENT_DIR="${RDAGENT_DIR:-/root/RD-Agent}"   # <-- change this to your repo path

if [ "$1" = "run" ]; then
    if [ "${@: -1}" = "env" ]; then
        echo "PATH=$RDAGENT_DIR/.venv/bin"
        exit 0
    fi
fi
echo "conda shim: unsupported command: $*" >&2
exit 1
