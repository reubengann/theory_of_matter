param(
    [string]$RepoRoot,
    [string]$OutputDir,
    [string]$PythonVersion = "3.12",
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) {
    $RepoRoot = Split-Path $scriptDir -Parent
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $scriptDir "dist"
}

$runtimeInformation = [System.Runtime.InteropServices.RuntimeInformation]
$osPlatform = [System.Runtime.InteropServices.OSPlatform]
$architecture = $runtimeInformation::OSArchitecture.ToString()
if ($runtimeInformation::IsOSPlatform($osPlatform::Windows) -and $architecture -eq "X64") {
    $platform = "windows"
    $bundleArchitecture = "x86_64"
    $venvBinDirectory = "Scripts"
    $executableSuffix = ".exe"
    $bundleScripts = @("install.ps1", "run-jupyter.ps1")
}
elseif ($runtimeInformation::IsOSPlatform($osPlatform::Linux) -and $architecture -eq "X64") {
    $platform = "linux"
    $bundleArchitecture = "x86_64"
    $venvBinDirectory = "bin"
    $executableSuffix = ""
    $bundleScripts = @("install.sh", "run-jupyter.sh")
}
elseif ($runtimeInformation::IsOSPlatform($osPlatform::OSX) -and $architecture -eq "Arm64") {
    $platform = "macos"
    $bundleArchitecture = "arm64"
    $venvBinDirectory = "bin"
    $executableSuffix = ""
    $bundleScripts = @("install.sh", "run-jupyter.sh")
}
else {
    throw "Unsupported build platform: $($runtimeInformation::OSDescription) $architecture. Supported targets are Windows x64, Linux x64, and macOS ARM64."
}

$requirementsInPath = Join-Path $scriptDir "requirements.in"
$packageManifestPath = Join-Path $scriptDir "distribution-packages.txt"
$sourceManifestPath = Join-Path $scriptDir "sources.json"
$distributionSource = Join-Path $scriptDir "distribution"
$archiveScript = Join-Path $scriptDir "scripts/create-archive.py"
$customCssPath = Join-Path $scriptDir "assets/custom.css"
$mathSettingsPath = Join-Path $scriptDir "assets/jupyterlab-math-notebook-tools-settings.json"
$ipythonStartupPath = Join-Path $scriptDir "assets/ipython-startup.py"
$buildRoot = Join-Path $scriptDir ".build-distribution/$platform-$bundleArchitecture"
$buildVenv = Join-Path $buildRoot "build-venv"
$resolveVenv = Join-Path $buildRoot "resolve-venv"
$localWheelDir = Join-Path $buildRoot "local-wheels"
$stageDir = Join-Path $buildRoot "stage"
$wheelDir = Join-Path $stageDir "wheels"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE`: $Command $($Arguments -join ' ')"
        }
    }
    finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Remove-DirectoryWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowFailure
    )

    if (-not (Test-Path $Path)) {
        return
    }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if ($attempt -lt 5) {
                Start-Sleep -Seconds $attempt
            }
            elseif ($AllowFailure) {
                Write-Warning "Could not remove temporary directory '$Path': $_"
            }
            else {
                throw
            }
        }
    }
}

function Get-VenvExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Venv,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return Join-Path (Join-Path $Venv $venvBinDirectory) "$Name$executableSuffix"
}

foreach ($requiredFile in @(
    $requirementsInPath,
    $packageManifestPath,
    $sourceManifestPath,
    $archiveScript,
    $customCssPath,
    $mathSettingsPath,
    $ipythonStartupPath
) + @($bundleScripts | ForEach-Object { Join-Path $distributionSource $_ })) {
    if (-not (Test-Path $requiredFile -PathType Leaf)) {
        throw "Required distribution file not found: $requiredFile"
    }
}

$sourceManifest = Get-Content $sourceManifestPath -Raw | ConvertFrom-Json
$sources = @($sourceManifest.repositories)
if ($sources.Count -eq 0) {
    throw "No source repositories were found in $sourceManifestPath"
}
$localRepos = @($sources | Where-Object { $_.buildWheel })
$extensionRepos = @($sources | Where-Object { $_.buildJupyterLabExtension })
$equationForgeSources = @($sources | Where-Object { $_.buildEquationForge })
if ($equationForgeSources.Count -ne 1) {
    throw "sources.json must identify exactly one Equation Forge build repository."
}

foreach ($source in $sources) {
    $repoPath = Join-Path $RepoRoot $source.name
    if (-not (Test-Path $repoPath -PathType Container)) {
        throw "Required repository not found: $repoPath"
    }
}

$uvCommand = Get-Command uv -ErrorAction SilentlyContinue
$npmCommand = Get-Command npm -ErrorAction SilentlyContinue
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if (-not $uvCommand) {
    throw "uv is required on the build machine: https://docs.astral.sh/uv/"
}
if (-not $npmCommand) {
    throw "Node.js/npm is required on the build machine."
}
if (-not $gitCommand) {
    throw "git is required on the build machine."
}
$uv = $uvCommand.Source
$npm = $npmCommand.Source
$git = $gitCommand.Source

$packageNames = @(
    Get-Content $packageManifestPath |
        ForEach-Object { ($_ -split "#", 2)[0].Trim() } |
        Where-Object { $_ }
)
if ($packageNames.Count -eq 0) {
    throw "No local package names were found in $packageManifestPath"
}

Remove-DirectoryWithRetry -Path $buildRoot
New-Item $localWheelDir -ItemType Directory -Force | Out-Null
New-Item $wheelDir -ItemType Directory -Force | Out-Null
New-Item $OutputDir -ItemType Directory -Force | Out-Null

Write-Host "Building theory-of-matter for $platform $bundleArchitecture..."
Write-Host "Provisioning the Python $PythonVersion build environment..."
Invoke-Checked -Command $uv -Arguments @("python", "install", $PythonVersion)
Invoke-Checked -Command $uv -Arguments @(
    "venv",
    "--python",
    $PythonVersion,
    "--seed",
    $buildVenv
)
$buildPython = Get-VenvExecutable -Venv $buildVenv -Name "python"
$buildBin = Join-Path $buildVenv $venvBinDirectory
$env:PATH = "$buildBin$([IO.Path]::PathSeparator)$env:PATH"
Invoke-Checked -Command $uv -Arguments @(
    "pip",
    "install",
    "--python",
    $buildPython,
    "build",
    "hatch",
    "hatch-jupyter-builder",
    "jupyterlab>=4,<5"
)
$jlpm = Get-VenvExecutable -Venv $buildVenv -Name "jlpm"
if (-not (Test-Path $jlpm -PathType Leaf)) {
    throw "jlpm was not installed into the build environment."
}

$equationForge = Join-Path $RepoRoot $equationForgeSources[0].name
Write-Host "Building equation-forge..."
if (Test-Path (Join-Path $equationForge "package-lock.json") -PathType Leaf) {
    Invoke-Checked -Command $npm -Arguments @("ci") -WorkingDirectory $equationForge
}
else {
    Invoke-Checked -Command $npm -Arguments @("install") -WorkingDirectory $equationForge
}
Invoke-Checked -Command $npm -Arguments @("run", "build:core") -WorkingDirectory $equationForge
Invoke-Checked -Command $npm -Arguments @("run", "build:ui") -WorkingDirectory $equationForge

foreach ($source in $extensionRepos) {
    $repoPath = Join-Path $RepoRoot $source.name
    Write-Host "Building prebuilt JupyterLab assets for $($source.name)..."
    Invoke-Checked -Command $jlpm -Arguments @("install", "--immutable") -WorkingDirectory $repoPath
    Invoke-Checked -Command $jlpm -Arguments @("clean:all") -WorkingDirectory $repoPath
    Invoke-Checked -Command $jlpm -Arguments @("build:prod") -WorkingDirectory $repoPath
}

foreach ($source in $localRepos) {
    $repoPath = Join-Path $RepoRoot $source.name
    Write-Host "Building Python wheel for $($source.name)..."
    Invoke-Checked -Command $buildPython -Arguments @(
        "-m",
        "build",
        "--wheel",
        "--outdir",
        $localWheelDir,
        $repoPath
    )
}

$localWheels = @(Get-ChildItem $localWheelDir -Filter "*.whl" -File)
if ($localWheels.Count -ne $localRepos.Count) {
    throw "Expected $($localRepos.Count) local wheels, found $($localWheels.Count)."
}

Write-Host "Resolving the complete binary wheel dependency set..."
$wheelArguments = @(
    "-m",
    "pip",
    "wheel",
    "--only-binary=:all:",
    "--wheel-dir",
    $wheelDir,
    "--requirement",
    $requirementsInPath
) + @($localWheels.FullName)
Invoke-Checked -Command $buildPython -Arguments $wheelArguments

Write-Host "Generating the resolved install manifest..."
Invoke-Checked -Command $uv -Arguments @(
    "venv",
    "--python",
    $PythonVersion,
    $resolveVenv
)
$resolvePython = Get-VenvExecutable -Venv $resolveVenv -Name "python"
$installArguments = @(
    "pip",
    "install",
    "--offline",
    "--python",
    $resolvePython,
    "--no-index",
    "--find-links",
    $wheelDir,
    "--requirement",
    $requirementsInPath
) + $packageNames
Invoke-Checked -Command $uv -Arguments $installArguments

$requirementsLock = Join-Path $stageDir "requirements-lock.txt"
$frozenRequirements = & $uv pip freeze --python $resolvePython
if ($LASTEXITCODE -ne 0) {
    throw "Unable to generate requirements-lock.txt"
}
$frozenRequirements | Sort-Object | Set-Content $requirementsLock -Encoding utf8

if (-not $SkipSmokeTest) {
    Write-Host "Smoke-testing the wheelhouse without using package indexes..."
    Invoke-Checked -Command $uv -Arguments @("pip", "check", "--python", $resolvePython)
    Invoke-Checked -Command $resolvePython -Arguments @(
        "-c",
        "import matterlib, jupyterlab, jupyterlab_sympy_assistant, jupyterlab_math_notebook_tools, jupyterlab_equation_forge, jupyterlab_excalidraw, jupyterlab_find_in_folder"
    )

    $resolveBin = Join-Path $resolveVenv $venvBinDirectory
    $env:PATH = "$resolveBin$([IO.Path]::PathSeparator)$env:PATH"
    $jupyter = Get-VenvExecutable -Venv $resolveVenv -Name "jupyter"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $labextensionOutput = & $jupyter labextension list 2>&1
        $labextensionExitCode = $LASTEXITCODE
        $serverExtensionOutput = & $jupyter server extension list 2>&1
        $serverExtensionExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($labextensionExitCode -ne 0) {
        throw "JupyterLab extension discovery failed."
    }
    $labextensionOutput | ForEach-Object { Write-Host $_ }
    foreach ($extensionName in @(
        "jupyterlab-sympy-assistant",
        "jupyterlab_math_notebook_tools",
        "jupyterlab-equation-forge",
        "jupyterlab-excalidraw",
        "jupyterlab-find-in-folder"
    )) {
        if (($labextensionOutput -join "`n") -notmatch [regex]::Escape($extensionName)) {
            throw "Bundled JupyterLab extension was not discovered: $extensionName"
        }
    }

    if ($serverExtensionExitCode -ne 0) {
        throw "Jupyter Server extension discovery failed."
    }
    $serverExtensionOutput | ForEach-Object { Write-Host $_ }
    foreach ($extensionName in @(
        "jupyterlab_sympy_assistant",
        "jupyterlab_find_in_folder"
    )) {
        if (($serverExtensionOutput -join "`n") -notmatch [regex]::Escape($extensionName)) {
            throw "Bundled Jupyter Server extension was not discovered: $extensionName"
        }
    }
}

Write-Host "Assembling the portable bundle..."
$ipythonStartupDir = Join-Path $stageDir "config/ipython/profile_default/startup"
$customCssDir = Join-Path $stageDir "config/jupyter/custom"
$mathSettingsDir = Join-Path $stageDir "config/jupyter/lab/user-settings/jupyterlab_math_notebook_tools"
New-Item $ipythonStartupDir -ItemType Directory -Force | Out-Null
New-Item $customCssDir -ItemType Directory -Force | Out-Null
New-Item $mathSettingsDir -ItemType Directory -Force | Out-Null
Copy-Item $ipythonStartupPath (Join-Path $ipythonStartupDir "00_jupyterlab_setup.py")
Copy-Item $customCssPath (Join-Path $customCssDir "custom.css")
Copy-Item $mathSettingsPath (Join-Path $mathSettingsDir "plugin.jupyterlab-settings")
foreach ($fileName in $bundleScripts) {
    Copy-Item (Join-Path $distributionSource $fileName) (Join-Path $stageDir $fileName)
}
if ($platform -ne "windows") {
    $chmod = (Get-Command chmod -ErrorAction Stop).Source
    Invoke-Checked -Command $chmod -Arguments @(
        "+x",
        (Join-Path $stageDir "install.sh"),
        (Join-Path $stageDir "run-jupyter.sh")
    )
}

$wheelManifest = Join-Path $stageDir "wheel-manifest.sha256"
Get-ChildItem $wheelDir -Filter "*.whl" -File |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant()
        "$hash  wheels/$($_.Name)"
    } |
    Set-Content $wheelManifest -Encoding ascii

$sourceCommits = [ordered]@{}
foreach ($source in $sources) {
    $repoPath = Join-Path $RepoRoot $source.name
    $commit = (& $git -C $repoPath rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine the commit for $($source.name)."
    }
    $sourceCommits[$source.name] = $commit
}

$metadata = [ordered]@{
    name = "theory-of-matter"
    platform = $platform
    architecture = $bundleArchitecture
    python = $PythonVersion
    built_at_utc = [DateTime]::UtcNow.ToString("o")
    local_projects = $packageNames
    wheel_count = @(Get-ChildItem $wheelDir -Filter "*.whl" -File).Count
    sources = $sourceCommits
}
$metadata |
    ConvertTo-Json -Depth 6 |
    Set-Content (Join-Path $stageDir "build-metadata.json") -Encoding utf8
$PythonVersion |
    Set-Content (Join-Path $stageDir "python-version.txt") -Encoding ascii

$pythonTag = $PythonVersion.Replace(".", "")
$artifactName = "theory-of-matter-$platform-$bundleArchitecture-py$pythonTag.zip"
$artifactPath = Join-Path $OutputDir $artifactName
if (Test-Path $artifactPath) {
    Remove-Item $artifactPath -Force
}
Invoke-Checked -Command $buildPython -Arguments @(
    $archiveScript,
    $stageDir,
    $artifactPath
)
Remove-DirectoryWithRetry -Path $buildVenv -AllowFailure
Remove-DirectoryWithRetry -Path $resolveVenv -AllowFailure
Remove-DirectoryWithRetry -Path $buildRoot -AllowFailure

Write-Host "Distribution created: $artifactPath"
