import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// Page scaffold that keeps [PrimaryHeader] edge-to-edge under the status bar,
/// while lifting body content above the Android 3-button / gesture navigation bar.
///
/// Use this instead of [Scaffold] on every pushed page (not tab roots inside
/// [BeeApp], which already pad via the bottom navigation bar).
class BeeScaffold extends StatelessWidget {
  final Widget body;
  final Color? backgroundColor;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final bool resizeToAvoidBottomInset;
  final bool protectSystemNav;

  const BeeScaffold({
    super.key,
    required this.body,
    this.backgroundColor,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.resizeToAvoidBottomInset = true,
    this.protectSystemNav = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? BeeTokens.scaffoldBackground(context);

    if (!protectSystemNav) {
      return Scaffold(
        backgroundColor: bg,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        extendBody: extendBody,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      );
    }

    // Custom bottom bars (often wrap themselves in SafeArea) keep the original
    // MediaQuery padding so they can inset correctly.
    if (bottomNavigationBar != null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        extendBody: extendBody,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      );
    }

    final media = MediaQuery.of(context);
    final inset = media.padding.bottom;

    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(bottom: 0),
        viewPadding: media.viewPadding.copyWith(bottom: 0),
      ),
      child: Scaffold(
        backgroundColor: bg,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: inset > 0
            ? ColoredBox(
                color: bg,
                child: SizedBox(height: inset),
              )
            : null,
        extendBody: extendBody,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      ),
    );
  }
}
