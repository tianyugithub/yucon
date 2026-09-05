import 'package:flutter/material.dart';

class ThemeDefine {
  static const int _primaryValue = 0xFFFA2C19;

  static const MaterialColor kColorBlue = MaterialColor(
    _primaryValue,
    <int, Color>{
      50: Color(0xFFFFEBE8),
      100: Color(0xFFFFD2CC),
      200: Color(0xFFFFA89E),
      300: Color(0xFFFF7E70),
      400: Color(0xFFFF5C4B),
      500: Color(_primaryValue),
      600: Color(0xFFE1251B),
      700: Color(0xFFC81E16),
      800: Color(0xFFA31812),
      900: Color(0xFF7A100C),
    },
  );

  static const Color kColorPrimary = Color(_primaryValue);
  static const Color kColorPrimaryEnd = Color(0xFFFA6419);
  static const Color kColorPrimaryDark = Color(0xFFF2270C);
  static const Color kColorGrey = Color(0xFF7D8490);
  static const Color kColorGreenBright = Color(0xFF21A366);
  static const Color kColorWarning = Color(0xFFED8A19);

  static const Color kColorTitle = Color(0xFF1A1A1A);
  static const Color kColorTitle2 = Color(0xFF7D8490);
  static const Color kColorText = Color(0xFF7D8490);
  static const Color kColorDisable = Color(0xFFCCCCCC);
  static const Color kColorPage = Color(0xFFF5F5F5);
  static const Color kColorCard = Color(0xFFFFFFFF);
  static const Color kColorLine = Color(0xFFECEEF2);
  static const Color kColorBorder = Color(0xFFECEEF2);
  static const Color kColorSoft = Color(0xFFFFF0ED);
  static const Color kColorTabInactive = Color(0xFF848B96);

  static const Color kColorDarkPage = Color(0xFF131313);
  static const Color kColorDarkCard = Color(0xFF1B1B1B);
  static const Color kColorDarkLine = Color(0xFF323233);
  static const Color kColorDarkTitle = Color(0xFFFFFFFF);
  static const Color kColorDarkText = Color(0xB3E8E6E3);

  static const String kThemeSystem = "system";
  static const String kThemeLight = "light";
  static const String kThemeDark = "dark";

  static const BorderRadiusGeometry kBorderRadius = BorderRadius.all(
    Radius.circular(14),
  );
  static const double kCardRadius = 14;
  static const double kPagePad = 15;
  static const List<BoxShadow> kCardShadow = [
    BoxShadow(color: Color(0x14201C27), blurRadius: 20, offset: Offset(0, 8)),
  ];

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [kColorPrimary, kColorPrimaryEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
