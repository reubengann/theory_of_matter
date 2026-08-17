$ErrorActionPreference = "Stop"
$bundleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$jupyter = Join-Path $bundleDir ".venv\Scripts\jupyter.exe"

if (-not (Test-Path $jupyter -PathType Leaf)) {
    throw "JupyterLab is not installed. Run .\install.ps1 first."
}

$env:IPYTHONDIR = Join-Path $bundleDir "config\ipython"
$env:JUPYTER_CONFIG_DIR = Join-Path $bundleDir "config\jupyter"
Set-Location $bundleDir

& $jupyter lab --custom-css @args
exit $LASTEXITCODE
