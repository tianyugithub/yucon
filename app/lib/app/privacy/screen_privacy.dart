import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

const _privacyChannel = MethodChannel('cc.yucon.vault/proxy');

class ScreenSecure {
  static int _holds = 0;

  static Future<void> retain() async {
    _holds += 1;
    if (_holds == 1) {
      await _setNative(true);
    }
  }

  static Future<void> release() async {
    if (_holds == 0) {
      return;
    }
    _holds -= 1;
    if (_holds == 0) {
      await _setNative(false);
    }
  }

  static Future<void> _setNative(bool enable) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _privacyChannel.invokeMethod<void>('setSecureFlag', {
        'enable': enable,
      });
    } catch (_) {}
  }
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
