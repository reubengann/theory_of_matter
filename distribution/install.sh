#!/usr/bin/env bash
set -euo pipefail

requested_python_version="${PYTHON_VERSION:-}"
bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
wheel_dir="$bundle_dir/wheels"
requirements_path="$bundle_dir/requirements-lock.txt"
hash_manifest_path="$bundle_dir/wheel-manifest.sha256"
python_version_path="$bundle_dir/python-version.txt"
metadata_path="$bundle_dir/build-metadata.json"
venv_dir="$bundle_dir/.venv"

case "$(uname -s):$(uname -m)" in
    Linux:x86_64)
        expected_platform=linux
        expected_architecture=x86_64
        checksum_command=sha256sum
        ;;
    Darwin:arm64)
        expected_platform=macos
        expected_architecture=arm64
        checksum_command=shasum
        ;;
    *)
        printf 'This bundle installer supports Linux x86_64 and macOS ARM64 only.\n' >&2
        exit 1
        ;;
esac

for required_path in \
    "$wheel_dir" \
    "$requirements_path" \
    "$hash_manifest_path" \
    "$python_version_path" \
    "$metadata_path"; do
    if [[ ! -e "$required_path" ]]; then
        printf 'Required bundle path not found: %s\n' "$required_path" >&2
        exit 1
    fi
done

if ! grep -Eq \
    "\"platform\"[[:space:]]*:[[:space:]]*\"$expected_platform\"" \
    "$metadata_path" ||
    ! grep -Eq \
        "\"architecture\"[[:space:]]*:[[:space:]]*\"$expected_architecture\"" \
        "$metadata_path"; then
    printf 'Bundle metadata does not target %s %s.\n' \
        "$expected_platform" "$expected_architecture" >&2
    exit 1
fi

python_version="$(tr -d '[:space:]' <"$python_version_path")"
if [[ -z "$python_version" ]]; then
    printf 'Bundle Python version is empty: %s\n' "$python_version_path" >&2
    exit 1
fi
if [[ -n "$requested_python_version" && "$requested_python_version" != "$python_version" ]]; then
    printf 'This bundle requires Python %s, not %s.\n' \
        "$python_version" "$requested_python_version" >&2
    exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
    if ! command -v curl >/dev/null 2>&1; then
        printf 'curl is required to install uv. Install curl and rerun install.sh.\n' >&2
        exit 1
    fi
    printf 'uv was not found; installing it with the official Astral installer...\n'
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi
if ! command -v uv >/dev/null 2>&1; then
    printf 'uv installation completed, but uv is not on PATH. Open a new shell and rerun install.sh.\n' >&2
    exit 1
fi
if ! command -v "$checksum_command" >/dev/null 2>&1; then
    printf '%s is required to verify the wheel bundle.\n' "$checksum_command" >&2
    exit 1
fi

printf 'Verifying bundled wheels...\n'
if [[ "$checksum_command" == sha256sum ]]; then
    (
        cd "$bundle_dir"
        sha256sum --check "$(basename "$hash_manifest_path")"
    )
else
    (
        cd "$bundle_dir"
        shasum -a 256 --check "$(basename "$hash_manifest_path")"
    )
fi

printf 'Installing CPython %s with uv (if needed)...\n' "$python_version"
uv python install "$python_version"

printf 'Creating the local virtual environment...\n'
uv venv --clear --python "$python_version" "$venv_dir"

printf 'Installing packages from the bundled wheelhouse...\n'
uv pip install \
    --offline \
    --python "$venv_dir/bin/python" \
    --no-index \
    --find-links "$wheel_dir" \
    --requirement "$requirements_path"
uv pip check --python "$venv_dir/bin/python"

printf '\nInstallation complete.\n'
printf 'Launch JupyterLab with: ./run-jupyter.sh\n'
