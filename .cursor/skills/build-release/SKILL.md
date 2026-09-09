---
name: build-release
description: >-
  Build BeeCount Flutter release APK and/or Windows exe. Rename the APK to
  app-prod-release.{version}.{yyyy}.{M}.{d}.apk, zip Windows Release as
  Release.{version}.{yyyy}.{M}.{d}.zip, then bundle both into
  build/result/BeeCount.{version}.{date}.zip. Use when the user asks to
  打 release、构建 app/exe、打包 Windows、压压缩包, 或把 apk 和 exe 一起压缩,
  or flutter build windows/apk --release.
---

# Build BeeCount release

Work from `beecount_client`.

## AI key (required for in-app GLM)

Copy `.cursor/zhipu.env.example` to `.cursor/zhipu.env` and set `ZHIPU_API_KEY`. The key is compiled into the APK/exe; users do not configure it.

```powershell
$defineArgs = @()
$envFile = Join-Path (Get-Location) ".cursor\zhipu.env"
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') {
      $defineArgs += "--dart-define=$($Matches[1])=$($Matches[2].Trim().Trim('\"'))"
    }
  }
} else {
  Write-Warning "Missing .cursor/zhipu.env — GLM AI key will not be baked in"
}
```

Pass `@defineArgs` to every `flutter build` / `flutter run`.

## Commands

```powershell
flutter pub get
flutter build apk --flavor prod --release @defineArgs
flutter build windows --release @defineArgs
```

Windows needs Developer Mode (symlinks) and VS 2022 workload **Desktop development with C++**.

Stamp: `{pubspec version}.{year}.{month}.{day}` (month/day **not** zero-padded), e.g. `3.0.1.2026.9.9`.

## Rename APK (required after apk)

Flutter writes `build/app/outputs/flutter-apk/app-prod-release.apk`. Always copy to a stamped name:

```powershell
powershell -NoProfile -File .cursor/skills/build-release/scripts/pack-apk.ps1
```

Output: `build/app/outputs/flutter-apk/app-prod-release.{version}.{yyyy}.{M}.{d}.apk`  
Example: `app-prod-release.3.0.1.2026.9.9.apk`

## Zip Windows Release (required after exe)

Windows output dir: `build/windows/x64/runner/Release/` (must ship the whole folder, not only `beecount.exe`).

```powershell
powershell -NoProfile -File .cursor/skills/build-release/scripts/pack-windows-release.ps1
```

Output: `build/windows/x64/runner/Release.{version}.{yyyy}.{M}.{d}.zip`  
Zip root folder matches that basename (exe + dlls + `data\`). Exclude `*.lnk`.  
This script also calls `pack-result.ps1` when the stamped APK exists.

## Bundle into `build/result/` (required after both exist)

```powershell
powershell -NoProfile -File .cursor/skills/build-release/scripts/pack-result.ps1
```

Output: `build/result/BeeCount.{version}.{yyyy}.{M}.{d}.zip`  
Contains: `Release.{version}.{yyyy}.{M}.{d}.zip` and `app-prod-release.{version}.{yyyy}.{M}.{d}.apk`.

Report the stamped APK, Windows zip, and result zip paths.
