$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $workspaceRoot 'src'
$sourceCore = Join-Path $sourceRoot 'rfsuite'
$sourceToolEntrypoint = Join-Path $sourceRoot 'main.lua'
$sourceWidgetRoot = Join-Path $sourceRoot 'widgets\rfsuite'
$sourceUserRoot = Join-Path $sourceRoot 'rfsuite.user'

$toolsRoot = Join-Path $workspaceRoot 'simulator\SCRIPTS\TOOLS'
$widgetsRoot = Join-Path $workspaceRoot 'simulator\WIDGETS'

$targetCore = Join-Path $toolsRoot 'rfsuite-core'
$targetToolEntrypoint = Join-Path $toolsRoot 'rfsuite.lua'
$targetUserRoot = Join-Path $toolsRoot 'rfsuite.user'
$targetWidgetRoot = Join-Path $widgetsRoot 'rfsuite'

$legacyToolFolder = Join-Path $toolsRoot 'rfsuite'

if (-not (Test-Path $sourceRoot)) {
    throw "Source folder not found: $sourceRoot"
}

if (-not (Test-Path $sourceCore)) {
    throw "Core source folder not found: $sourceCore"
}

if (-not (Test-Path $sourceToolEntrypoint)) {
    throw "Tool entrypoint not found: $sourceToolEntrypoint"
}

if (-not (Test-Path $sourceWidgetRoot)) {
    throw "Widget source folder not found: $sourceWidgetRoot"
}

if (-not (Test-Path $sourceUserRoot)) {
    throw "User source folder not found: $sourceUserRoot"
}

if (-not (Test-Path $toolsRoot)) {
    New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
}

if (-not (Test-Path $widgetsRoot)) {
    New-Item -ItemType Directory -Path $widgetsRoot -Force | Out-Null
}

if (Test-Path $legacyToolFolder) {
    Remove-Item -Path $legacyToolFolder -Recurse -Force
}

if (Test-Path $targetCore) {
    Remove-Item -Path $targetCore -Recurse -Force
}
New-Item -ItemType Directory -Path $targetCore -Force | Out-Null
Copy-Item -Path (Join-Path $sourceCore '*') -Destination $targetCore -Recurse -Force

Copy-Item -Path $sourceToolEntrypoint -Destination $targetToolEntrypoint -Force

if (-not (Test-Path $targetUserRoot)) {
    New-Item -ItemType Directory -Path $targetUserRoot -Force | Out-Null
}

$targetPreferencesFile = Join-Path $targetUserRoot 'preferences.ini'
if (-not (Test-Path $targetPreferencesFile)) {
    Copy-Item -Path (Join-Path $sourceUserRoot 'preferences.ini') -Destination $targetPreferencesFile -Force
}

if (Test-Path $targetWidgetRoot) {
    Remove-Item -Path $targetWidgetRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $targetWidgetRoot -Force | Out-Null
Copy-Item -Path (Join-Path $sourceWidgetRoot '*') -Destination $targetWidgetRoot -Recurse -Force

Write-Host "RFSuite demo deployed to:"
Write-Host "  Tool entrypoint: $targetToolEntrypoint"
Write-Host "  Core package:    $targetCore"
Write-Host "  User data:       $targetUserRoot"
Write-Host "  Widget package:  $targetWidgetRoot"
