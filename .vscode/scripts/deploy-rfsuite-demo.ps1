$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $workspaceRoot 'src'
$targetRoot = Join-Path $workspaceRoot 'simulator\SCRIPTS\TOOLS\rfsuite'

if (-not (Test-Path $sourceRoot)) {
    throw "Source folder not found: $sourceRoot"
}

if (-not (Test-Path $targetRoot)) {
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
}

Get-ChildItem -Path $targetRoot -Force | Remove-Item -Recurse -Force
Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $targetRoot -Recurse -Force

Write-Host "RFSuite demo deployed to: $targetRoot"
