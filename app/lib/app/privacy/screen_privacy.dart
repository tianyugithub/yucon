import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class ScreenSecure {
  static Future<void> retain() async {}

  static Future<void> release() async {}
}

class SecureScope extends StatefulWidget {
  const SecureScope({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends State<SecureScope> {
  @override
  void initState() {
    super.initState();
    ScreenSecure.retain();
  }

  @override
  void dispose() {
    ScreenSecure.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppPrivacyCover extends StatelessWidget {
  const AppPrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = dark ? ThemeDefine.kColorDarkPage : ThemeDefine.kColorPage;
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: page,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: const Center(child: BrandMark(size: 72)),
          ),
        ),
      ),
    );
  }
}
