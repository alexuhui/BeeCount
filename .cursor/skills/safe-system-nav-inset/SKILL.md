---
name: safe-system-nav-inset
description: >-
  Use when adding or editing BeeCount Flutter pages, scaffolds, ListViews,
  bottom bars, or sheets; or when content is covered by the Android 3-button
  navigation bar / gesture bar / virtual keys, or iOS home indicator.
---

# Safe system navigation inset

Pushed pages must sit above the system navigation bar. Tab roots inside `BeeApp` already get this from `_BeeBottomBar`. Every other page must use `BeeScaffold`.

## Rule

- Pushed route / full-screen page → `BeeScaffold` (not `Scaffold`)
- Tab root (`HomePage`, `AnalyticsPage`, `DiscoverPage`, `MinePage`) → keep `Scaffold`; do not wrap with `BeeScaffold`
- Custom `bottomNavigationBar` that already uses `SafeArea` → `BeeScaffold` still OK; it will not double-pad
- Immersive galleries that hide system UI → `BeeScaffold(protectSystemNav: false)`

`PrimaryHeader` already handles the **top** status bar (`SafeArea(bottom: false)`). Do not wrap the whole page in `SafeArea(top: true)` or the header will no longer paint into the status bar.

## Pattern

```dart
return BeeScaffold(
  backgroundColor: BeeTokens.scaffoldBackground(context),
  body: Column(
    children: [
      const PrimaryHeader(title: '…', showBack: true),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [ /* last item must be reachable */ ],
        ),
      ),
    ],
  ),
);
```

## Do not

- Use raw `Scaffold` on a pushed page
- Rely on "the list is short so overlap is fine"
- Add ad-hoc `SizedBox(height: MediaQuery.padding.bottom)` as the only fix on a new page — `BeeScaffold` already consumes that inset
- Pad the entire `MaterialApp` (breaks the tab bar, which is supposed to extend into the inset)

## Bottom sheets / dialogs

Modal sheets and pickers still need `SafeArea(top: false)` (see `WheelDatePicker`). `BeeScaffold` does not wrap overlays.
