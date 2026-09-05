import 'package:flutter/material.dart';
import 'package:vault/screens/theme_define.dart';

class ThemeDataDark {
  static const Color mainColor = ThemeDefine.kColorDarkCard;
  static const Color mainBgColor = ThemeDefine.kColorDarkPage;

  static ThemeData theme(BuildContext context) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: ThemeDefine.kColorPrimaryDark,
      onPrimary: Colors.white,
      secondary: ThemeDefine.kColorPrimaryEnd,
      onSecondary: Colors.white,
      error: ThemeDefine.kColorPrimaryDark,
      onError: Colors.white,
      surface: ThemeDefine.kColorDarkPage,
      onSurface: ThemeDefine.kColorDarkTitle,
      onSurfaceVariant: ThemeDefine.kColorDarkText,
      secondaryContainer: Color(0xFF3A1A16),
      onSecondaryContainer: ThemeDefine.kColorPrimaryDark,
      outline: ThemeDefine.kColorDarkLine,
      outlineVariant: ThemeDefine.kColorDarkLine,
      surfaceContainerLowest: ThemeDefine.kColorDarkCard,
      surfaceContainerLow: ThemeDefine.kColorDarkCard,
      surfaceContainer: ThemeDefine.kColorDarkCard,
      surfaceContainerHigh: ThemeDefine.kColorDarkPage,
      surfaceContainerHighest: ThemeDefine.kColorDarkPage,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: ThemeDefine.kColorDarkLine,
      hintColor: ThemeDefine.kColorText,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: ThemeDefine.kColorDarkPage,
        foregroundColor: ThemeDefine.kColorDarkTitle,
        centerTitle: false,
        titleSpacing: 15,
      ),
      cardTheme: CardThemeData(
        color: ThemeDefine.kColorDarkCard,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ThemeDefine.kColorDarkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ThemeDefine.kColorDarkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(
        color: ThemeDefine.kColorDarkLine,
        space: 1,
        thickness: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: ThemeDefine.kColorDarkCard,
        filled: true,
        labelStyle: const TextStyle(color: ThemeDefine.kColorText),
        floatingLabelStyle: const TextStyle(color: ThemeDefine.kColorPrimaryDark),
        helperStyle: const TextStyle(color: ThemeDefine.kColorText),
        hintStyle: const TextStyle(color: ThemeDefine.kColorText),
        errorStyle: const TextStyle(color: ThemeDefine.kColorPrimaryDark),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: ThemeDefine.kColorDarkLine),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: ThemeDefine.kColorDarkLine),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: ThemeDefine.kColorPrimaryDark),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        iconColor: ThemeDefine.kColorDarkText,
        textColor: ThemeDefine.kColorDarkTitle,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ThemeDefine.kColorDarkLine;
            }
            return ThemeDefine.kColorPrimaryDark;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ThemeDefine.kColorPrimaryDark),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ThemeDefine.kColorPrimaryDark;
          }
          return ThemeDefine.kColorDarkLine;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ThemeDefine.kColorPrimaryDark,
        strokeWidth: 2,
      ),
      iconTheme: const IconThemeData(color: ThemeDefine.kColorDarkTitle),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ThemeDefine.kColorDarkCard,
        indicatorColor: const Color(0xFF3A1A16),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? ThemeDefine.kColorPrimaryDark
                : ThemeDefine.kColorDarkText,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            height: 1.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? ThemeDefine.kColorPrimaryDark
                : ThemeDefine.kColorDarkText,
          );
        }),
      ),
    );
  }
}
