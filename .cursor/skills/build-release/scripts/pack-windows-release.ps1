# Zip Windows Release as Release.{version}.{yyyy}.{M}.{d}.zip
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$pubspec = Join-Path $repoRoot "pubspec.yaml"
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $releaseDir "beecount.exe"))) {
  throw "Missing $releaseDir\beecount.exe — build windows release first"
}

$line = Select-String -Path $pubspec -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $line) { throw "No version in pubspec.yaml" }
$version = ($line.Matches[0].Groups[1].Value -split '\+')[0]

$now = Get-Date
$name = "Release.$version.$($now.Year).$($now.Month).$($now.Day)"
$outDir = Join-Path $repoRoot "build\windows\x64\runner"
$zipPath = Join-Path $outDir "$name.zip"
$stage = Join-Path $env:TEMP $name
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

Get-ChildItem $releaseDir -Force | Where-Object { $_.Extension -ne ".lnk" } | ForEach-Object {
  Copy-Item $_.FullName -Destination (Join-Path $stage $_.Name) -Recurse -Force
}

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Push-Location (Split-Path $stage -Parent)
try {
  tar.exe -a -cf $zipPath $name
  if ($LASTEXITCODE -ne 0) { throw "tar zip failed" }
}
finally {
  Pop-Location
  Remove-Item $stage -Recurse -Force
}

Write-Host $zipPath

$packResult = Join-Path $PSScriptRoot "pack-result.ps1"
if (Test-Path $packResult) {
  & $packResult
}
