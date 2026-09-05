import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault/screens/theme_data_dark.dart';
import 'package:vault/screens/theme_data_light.dart';
import 'package:vault/screens/theme_define.dart';

class Themes with ChangeNotifier {
  String _theme = ThemeDefine.kThemeLight;

  void setTheme(String theme, {bool notify = true}) {
    if (theme != ThemeDefine.kThemeSystem &&
        theme != ThemeDefine.kThemeLight &&
        theme != ThemeDefine.kThemeDark) {
      return;
    }
    _theme = theme;
    if (notify) {
      notifyListeners();
    }
  }

  bool isDark(BuildContext context) {
    if (_theme == ThemeDefine.kThemeDark) {
      return true;
    }
    if (_theme == ThemeDefine.kThemeLight) {
      return false;
    }
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  void apply(String theme) {
    setTheme(theme);
  }

  void toggleNight(BuildContext context) {
    apply(isDark(context) ? ThemeDefine.kThemeLight : ThemeDefine.kThemeDark);
  }

  String theme() => _theme;

  ThemeMode themeMode() {
    switch (_theme) {
      case ThemeDefine.kThemeSystem:
        return ThemeMode.system;
      case ThemeDefine.kThemeLight:
        return ThemeMode.light;
      case ThemeDefine.kThemeDark:
        return ThemeMode.dark;
    }
    return ThemeMode.light;
  }

  ThemeData themeData(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    switch (_theme) {
      case ThemeDefine.kThemeLight:
        return ThemeDataLight.theme(context);
      case ThemeDefine.kThemeDark:
        return ThemeDataDark.theme(context);
    }
    return brightness == Brightness.dark
        ? ThemeDataDark.theme(context)
        : ThemeDataLight.theme(context);
  }

  Brightness? getStatusBarIconBrightness(BuildContext context) {
    if (!Platform.isAndroid) {
      return null;
    }
    return isDark(context) ? Brightness.light : Brightness.dark;
  }
}
