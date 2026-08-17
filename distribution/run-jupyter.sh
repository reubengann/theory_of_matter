#!/usr/bin/env bash
set -euo pipefail

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
jupyter="$bundle_dir/.venv/bin/jupyter"

if [[ ! -x "$jupyter" ]]; then
    printf 'JupyterLab is not installed. Run ./install.sh first.\n' >&2
    exit 1
fi

export IPYTHONDIR="$bundle_dir/config/ipython"
export JUPYTER_CONFIG_DIR="$bundle_dir/config/jupyter"
cd "$bundle_dir"

exec "$jupyter" lab --custom-css "$@"
