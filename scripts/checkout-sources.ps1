param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string]$ManifestPath
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ManifestPath) {
    $ManifestPath = Join-Path (Split-Path $scriptDir -Parent) "sources.json"
}

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

if (-not (Test-Path $ManifestPath -PathType Leaf)) {
    throw "Source manifest not found: $ManifestPath"
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCommand) {
    throw "git is required to check out distribution sources."
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
if (-not $manifest.repositories) {
    throw "No repositories are declared in $ManifestPath"
}

New-Item $RepoRoot -ItemType Directory -Force | Out-Null
foreach ($repository in $manifest.repositories) {
    $destination = Join-Path $RepoRoot $repository.name
    if (Test-Path $destination) {
        throw "Checkout destination already exists: $destination"
    }

    Write-Host "Cloning $($repository.name) at $($repository.ref)..."
    Invoke-Checked -Command $gitCommand.Source -Arguments @(
        "clone",
        "--filter=blob:none",
        "--no-checkout",
        $repository.url,
        $destination
    )
    Invoke-Checked -Command $gitCommand.Source -Arguments @(
        "-C",
        $destination,
        "fetch",
        "--depth",
        "1",
        "origin",
        $repository.ref
    )
    Invoke-Checked -Command $gitCommand.Source -Arguments @(
        "-C",
        $destination,
        "checkout",
        "--detach",
        "FETCH_HEAD"
    )

    $commit = (& $gitCommand.Source -C $destination rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine the commit for $($repository.name)."
    }
    Write-Host "Checked out $($repository.name) at $commit"
}
