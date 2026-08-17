param(
    [string]$PythonVersion
)

$ErrorActionPreference = "Stop"
$bundleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wheelDir = Join-Path $bundleDir "wheels"
$requirementsPath = Join-Path $bundleDir "requirements-lock.txt"
$hashManifestPath = Join-Path $bundleDir "wheel-manifest.sha256"
$pythonVersionPath = Join-Path $bundleDir "python-version.txt"
$metadataPath = Join-Path $bundleDir "build-metadata.json"
$venvDir = Join-Path $bundleDir ".venv"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $Command $($Arguments -join ' ')"
    }
}

$runtimeInformation = [System.Runtime.InteropServices.RuntimeInformation]
$osPlatform = [System.Runtime.InteropServices.OSPlatform]
if (
    -not $runtimeInformation::IsOSPlatform($osPlatform::Windows) -or
    $runtimeInformation::OSArchitecture.ToString() -ne "X64"
) {
    throw "This bundle targets Windows x64."
}

foreach ($requiredPath in @(
    $wheelDir,
    $requirementsPath,
    $hashManifestPath,
    $pythonVersionPath,
    $metadataPath
)) {
    if (-not (Test-Path $requiredPath)) {
        throw "Required bundle path not found: $requiredPath"
    }
}

$metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
if ($metadata.platform -ne "windows" -or $metadata.architecture -ne "x86_64") {
    throw "Bundle metadata does not target Windows x64."
}

$bundlePythonVersion = (Get-Content $pythonVersionPath -Raw).Trim()
if (-not $bundlePythonVersion) {
    throw "Bundle Python version is empty: $pythonVersionPath"
}
if ($PythonVersion -and $PythonVersion -ne $bundlePythonVersion) {
    throw "This bundle requires Python $bundlePythonVersion, not $PythonVersion."
}
$PythonVersion = $bundlePythonVersion

$uvCommand = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvCommand) {
    Write-Host "uv was not found; installing it with the official Astral installer..."
    Invoke-Checked -Command "powershell" -Arguments @(
        "-ExecutionPolicy",
        "ByPass",
        "-Command",
        "irm https://astral.sh/uv/install.ps1 | iex"
    )

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
    $uvCommand = Get-Command uv -ErrorAction SilentlyContinue

    if (-not $uvCommand) {
        $uvCandidates = @(
            (Join-Path $env:USERPROFILE ".local\bin\uv.exe"),
            (Join-Path $env:USERPROFILE ".cargo\bin\uv.exe")
        )
        $uvPath = $uvCandidates |
            Where-Object { Test-Path $_ -PathType Leaf } |
            Select-Object -First 1
        if ($uvPath) {
            $uvCommand = Get-Command $uvPath
        }
    }
}
if (-not $uvCommand) {
    throw "uv installation completed, but uv could not be found. Open a new terminal and rerun install.ps1."
}
$uv = $uvCommand.Source

Write-Host "Verifying bundled wheels..."
foreach ($line in Get-Content $hashManifestPath) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }
    $parts = $line -split "\s+", 2
    if ($parts.Count -ne 2) {
        throw "Invalid wheel manifest line: $line"
    }
    $relativePath = $parts[1].Trim().Replace(
        "/",
        [string][IO.Path]::DirectorySeparatorChar
    )
    $wheelPath = Join-Path $bundleDir $relativePath
    if (-not (Test-Path $wheelPath -PathType Leaf)) {
        throw "Bundled wheel is missing: $relativePath"
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 $wheelPath).Hash.ToLowerInvariant()
    if ($actualHash -ne $parts[0].ToLowerInvariant()) {
        throw "Hash verification failed for $relativePath"
    }
}

Write-Host "Installing CPython $PythonVersion with uv (if needed)..."
Invoke-Checked -Command $uv -Arguments @("python", "install", $PythonVersion)

Write-Host "Creating the local virtual environment..."
Invoke-Checked -Command $uv -Arguments @(
    "venv",
    "--clear",
    "--python",
    $PythonVersion,
    $venvDir
)

$venvPython = Join-Path $venvDir "Scripts\python.exe"
Write-Host "Installing packages from the bundled wheelhouse..."
Invoke-Checked -Command $uv -Arguments @(
    "pip",
    "install",
    "--offline",
    "--python",
    $venvPython,
    "--no-index",
    "--find-links",
    $wheelDir,
    "--requirement",
    $requirementsPath
)
Invoke-Checked -Command $uv -Arguments @("pip", "check", "--python", $venvPython)

Write-Host ""
Write-Host "Installation complete."
Write-Host "Launch JupyterLab with: .\run-jupyter.ps1"
