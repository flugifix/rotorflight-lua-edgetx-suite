param(
    [string]$OutputDir,
    [string]$ZipName
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$deployScript = Join-Path $PSScriptRoot 'deploy-rfsuite-demo.ps1'

if (-not (Test-Path $deployScript)) {
    throw "Deploy script not found: $deployScript"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $workspaceRoot 'dist'
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($ZipName)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $ZipName = "rfsuite-radio-install-$timestamp.zip"
}

if ([System.IO.Path]::GetExtension($ZipName).ToLowerInvariant() -ne '.zip') {
    $ZipName = "$ZipName.zip"
}

$zipPath = Join-Path $OutputDir $ZipName

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rfsuite-radio-package-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $deployScript -Target radio -TargetRoot $stagingRoot

    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

    Write-Host "RFSuite install ZIP created:"
    Write-Host "  $zipPath"
    Write-Host "Contains top-level folders: SCRIPTS, WIDGETS, SOUNDS"
}
finally {
    if (Test-Path $stagingRoot) {
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
