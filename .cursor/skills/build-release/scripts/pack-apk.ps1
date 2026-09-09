# Copy prod release APK to app-prod-release.{version}.{yyyy}.{M}.{d}.apk
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$pubspec = Join-Path $repoRoot "pubspec.yaml"
$apkDir = Join-Path $repoRoot "build\app\outputs\flutter-apk"
$src = Join-Path $apkDir "app-prod-release.apk"
if (-not (Test-Path $src)) {
  $alt = Get-ChildItem $apkDir -Filter "app-prod-release*.apk" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '^app-prod-release\.\d+\.\d+\.\d+\.\d+\.\d+\.\d+\.apk$' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $alt) { throw "Missing $src" }
  $src = $alt.FullName
}

$line = Select-String -Path $pubspec -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $line) { throw "No version in pubspec.yaml" }
$version = ($line.Matches[0].Groups[1].Value -split '\+')[0]
$now = Get-Date
$dest = Join-Path $apkDir "app-prod-release.$version.$($now.Year).$($now.Month).$($now.Day).apk"
Copy-Item $src -Destination $dest -Force
Write-Host $dest
