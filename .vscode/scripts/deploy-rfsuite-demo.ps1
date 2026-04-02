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
Get-ChildItem -Path $targetCore -Filter '*.luac' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

Copy-Item -Path $sourceToolEntrypoint -Destination $targetToolEntrypoint -Force

if (-not (Test-Path $targetUserRoot)) {
    New-Item -ItemType Directory -Path $targetUserRoot -Force | Out-Null
}

$targetPreferencesFile = Join-Path $targetUserRoot 'preferences.ini'
if (-not (Test-Path $targetPreferencesFile)) {
    Copy-Item -Path (Join-Path $sourceUserRoot 'preferences.ini') -Destination $targetPreferencesFile -Force
}

function Get-ThemeMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$ThemeDir,
        [Parameter(Mandatory = $true)][string]$SourceName
    )

    $initFile = Join-Path $ThemeDir 'init.lua'
    if (-not (Test-Path $initFile)) {
        return $null
    }

    $content = Get-Content -Path $initFile -Raw
    $nameMatch = [regex]::Match($content, 'name\s*=\s*"([^"]+)"')
    if (-not $nameMatch.Success) {
        return $null
    }

    $configureMatch = [regex]::Match($content, 'configure\s*=\s*"([^"]+)"')
    $standaloneMatch = [regex]::Match($content, 'standalone\s*=\s*(true|false)')

    return [pscustomobject]@{
        name = $nameMatch.Groups[1].Value
        source = $SourceName
        folder = [System.IO.Path]::GetFileName($ThemeDir)
        configure = $(if ($configureMatch.Success) { $configureMatch.Groups[1].Value } else { $null })
        standalone = $(if ($standaloneMatch.Success) { $standaloneMatch.Groups[1].Value -eq 'true' } else { $false })
    }
}

function New-ThemeIndexFile {
    param(
        [Parameter(Mandatory = $true)][string]$TargetCoreDir,
        [Parameter(Mandatory = $true)][string]$TargetUserDir
    )

    $entries = @()

    $systemThemesDir = Join-Path $TargetCoreDir 'widgets\dashboard\themes'
    if (Test-Path $systemThemesDir) {
        Get-ChildItem -Path $systemThemesDir -Directory | ForEach-Object {
            $meta = Get-ThemeMetadata -ThemeDir $_.FullName -SourceName 'system'
            if ($null -ne $meta) { $entries += $meta }
        }
    }

    $userThemesDir = Join-Path $TargetUserDir 'dashboard'
    if (Test-Path $userThemesDir) {
        Get-ChildItem -Path $userThemesDir -Directory | ForEach-Object {
            $meta = Get-ThemeMetadata -ThemeDir $_.FullName -SourceName 'user'
            if ($null -ne $meta) { $entries += $meta }
        }
    }

    $indexFile = Join-Path $TargetCoreDir 'app\pages\settings\dashboard\theme_index.lua'
    $lines = @('return {')
    foreach ($entry in $entries) {
        $safeName = $entry.name.Replace('\', '\\').Replace('"', '\"')
        $safeFolder = $entry.folder.Replace('\', '\\').Replace('"', '\"')
        $configureValue = if ([string]::IsNullOrEmpty($entry.configure)) { 'nil' } else { '"' + $entry.configure.Replace('\', '\\').Replace('"', '\"') + '"' }
        $standaloneValue = if ($entry.standalone) { 'true' } else { 'false' }
        $lines += ('  { name = "' + $safeName + '", source = "' + $entry.source + '", folder = "' + $safeFolder + '", configure = ' + $configureValue + ', standalone = ' + $standaloneValue + ' },')
    }
    $lines += '}'

    Set-Content -Path $indexFile -Value $lines -Encoding ASCII
}

if (Test-Path $targetWidgetRoot) {
    Remove-Item -Path $targetWidgetRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $targetWidgetRoot -Force | Out-Null
Copy-Item -Path (Join-Path $sourceWidgetRoot '*') -Destination $targetWidgetRoot -Recurse -Force
Get-ChildItem -Path $targetWidgetRoot -Filter '*.luac' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

New-ThemeIndexFile -TargetCoreDir $targetCore -TargetUserDir $targetUserRoot

Write-Host "RFSuite demo deployed to:"
Write-Host "  Tool entrypoint: $targetToolEntrypoint"
Write-Host "  Core package:    $targetCore"
Write-Host "  User data:       $targetUserRoot"
Write-Host "  Widget package:  $targetWidgetRoot"
