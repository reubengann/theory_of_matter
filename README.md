# theory-of-matter

Builds self-contained, offline Python wheel distributions for the
theory-of-matter JupyterLab environment. Notebook content remains private and
is not part of this repository.

Each archive contains:

- a complete platform-specific Python wheelhouse;
- pinned resolved requirements and SHA-256 checksums;
- JupyterLab extensions built from the repositories in `sources.json`;
- IPython startup configuration, JupyterLab settings, and custom CSS; and
- scripts that create a local virtual environment and launch JupyterLab.

Recipients do not need git, Node.js, npm, conda, or a preinstalled Python.
The first install needs internet access only if `uv` or CPython must be
downloaded. Python packages are always installed from the archive.


## Install

Extract the archive into a writable folder without moving its internal files.

Windows:

```powershell
./install.ps1
./run-jupyter.ps1
```

Linux or macOS:

```bash
bash install.sh
./run-jupyter.sh
```

The installer verifies the wheel manifest, installs the recorded CPython
version through `uv`, recreates `.venv`, installs strictly from the bundled
wheelhouse, and runs `uv pip check`.

## Package selection

Direct runtime dependencies are in `requirements.in`. Local Python projects
included in the archive are in `distribution-packages.txt`. Source repository
locations and refs are in `sources.json`.

Repository-owned runtime configuration is kept as flat source files under
`assets/`. The builder maps those files into Jupyter and IPython's required
directory structure inside each finished archive.


## Supported bundles

- Windows x64
- Linux x64
- macOS Apple Silicon (ARM64)

Binary Python wheels are platform-specific, so each target is built and tested
on a native GitHub-hosted runner.

## Build with GitHub Actions

Open **Actions → Build distributions → Run workflow**. The workflow checks out
the public repositories declared in `sources.json`, builds and smoke-tests all
three platforms, and publishes ZIP files as workflow artifacts.

Builds also run when this repository's default branch changes. A
`repository_dispatch` event with type `dependency-updated` can trigger a build
later if dependency repositories are configured to send one.

`sources.json` accepts a branch, tag, or commit SHA in each `ref`. The resolved
commit for every repository is written to the bundle's
`build-metadata.json`. Pin refs to commit SHAs when an exactly reproducible
release is required.

## Build locally

Build requirements:

- PowerShell 7 (`pwsh`)
- `uv`
- Node.js and npm
- git
- the source repositories from `sources.json` as siblings under one repo root

On Windows, with all repositories under `C:\repos`:

```powershell
pwsh ./build-distribution.ps1 -RepoRoot C:\repos
```

On Linux or macOS:

```powershell
pwsh ./build-distribution.ps1 -RepoRoot "$HOME/repos"
```

To populate a clean source directory from `sources.json`:

```powershell
pwsh ./scripts/checkout-sources.ps1 -RepoRoot /path/to/repos
```

Artifacts are written to `dist/`. Use `-PythonVersion` to select another
Python minor version and `-SkipSmokeTest` only for diagnostic builds.
