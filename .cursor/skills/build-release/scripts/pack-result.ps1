# Bundle Windows Release zip + prod APK into build/result/
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$pubspec = Join-Path $repoRoot "pubspec.yaml"
$line = Select-String -Path $pubspec -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $line) { throw "No version in pubspec.yaml" }
$version = ($line.Matches[0].Groups[1].Value -split '\+')[0]

$now = Get-Date
$stamp = "$version.$($now.Year).$($now.Month).$($now.Day)"
$winZip = Join-Path $repoRoot "build\windows\x64\runner\Release.$stamp.zip"
$apk = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-prod-release.apk"
if (-not (Test-Path $winZip)) { throw "Missing $winZip" }
if (-not (Test-Path $apk)) { throw "Missing $apk" }

$resultDir = Join-Path $repoRoot "build\result"
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$bundleName = "BeeCount.$stamp"
$zipPath = Join-Path $resultDir "$bundleName.zip"
$stage = Join-Path $env:TEMP $bundleName
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item $winZip -Destination (Join-Path $stage (Split-Path $winZip -Leaf))
Copy-Item $apk -Destination (Join-Path $stage "app-prod-release.apk")

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Push-Location (Split-Path $stage -Parent)
try {
  tar.exe -a -cf $zipPath $bundleName
  if ($LASTEXITCODE -ne 0) { throw "tar zip failed" }
}
finally {
  Pop-Location
  Remove-Item $stage -Recurse -Force
}

Write-Host $zipPath
