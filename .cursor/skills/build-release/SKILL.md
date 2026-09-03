---
name: build-release
description: >-
  Build BeeCount Flutter release APK and/or Windows exe, then zip the full
  Windows Release folder as Release.{version}.{yyyy}.{M}.{d}.zip, then bundle
  that zip with app-prod-release.apk into build/result/BeeCount.{version}.{date}.zip.
  Use when the user asks to 打 release、构建 app/exe、打包 Windows、压压缩包,
  或把 apk 和 exe 一起压缩, or flutter build windows/apk --release.
---

# Build BeeCount release

Work from `beecount_client`.

## Commands

```bash
flutter pub get
flutter build apk --flavor prod --release
flutter build windows --release
```

APK: `build/app/outputs/flutter-apk/app-prod-release.apk`

Windows output dir: `build/windows/x64/runner/Release/` (must ship the whole folder, not only `beecount.exe`).

Windows needs Developer Mode (symlinks) and VS 2022 workload **Desktop development with C++**.

## Zip Windows Release (required after exe)

After a successful `flutter build windows --release`, always pack:

```powershell
powershell -NoProfile -File .cursor/skills/build-release/scripts/pack-windows-release.ps1
```

Archive name: `Release.{pubspec version}.{year}.{month}.{day}.zip`  
Example: `Release.3.0.1.2026.9.3.zip`  
Month/day are **not** zero-padded.

Output path: `build/windows/x64/runner/Release.{version}.{yyyy}.{M}.{d}.zip`  
Zip root folder matches that basename and contains exe + dlls + `data\`. Exclude `*.lnk`.

Report the zip full path to the user.

## Bundle APK + Windows zip into `build/result/` (required after both exist)

After the Windows zip exists and `app-prod-release.apk` exists, pack both into one archive:

```powershell
powershell -NoProfile -File .cursor/skills/build-release/scripts/pack-result.ps1
```

(`pack-windows-release.ps1` already calls this at the end.)

Output: `build/result/BeeCount.{version}.{yyyy}.{M}.{d}.zip`  
Contains: `Release.{version}.{yyyy}.{M}.{d}.zip` and `app-prod-release.apk`.

Report that path as the deliverable.
