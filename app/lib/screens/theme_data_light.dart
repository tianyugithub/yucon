import 'package:flutter/material.dart';
import 'package:vault/screens/theme_define.dart';

class ThemeDataLight {
  static const Color mainColor = ThemeDefine.kColorCard;
  static const Color mainBgColor = ThemeDefine.kColorPage;

  static ThemeData theme(BuildContext context) {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: ThemeDefine.kColorPrimary,
      onPrimary: Colors.white,
      secondary: ThemeDefine.kColorPrimaryEnd,
      onSecondary: Colors.white,
      error: ThemeDefine.kColorPrimary,
      onError: Colors.white,
      surface: ThemeDefine.kColorPage,
      onSurface: ThemeDefine.kColorTitle,
      onSurfaceVariant: ThemeDefine.kColorTitle2,
      secondaryContainer: Color(0xFFFFEBE8),
      onSecondaryContainer: ThemeDefine.kColorPrimary,
      outline: ThemeDefine.kColorBorder,
      outlineVariant: ThemeDefine.kColorLine,
      surfaceContainerLowest: ThemeDefine.kColorCard,
      surfaceContainerLow: ThemeDefine.kColorCard,
      surfaceContainer: ThemeDefine.kColorCard,
      surfaceContainerHigh: ThemeDefine.kColorPage,
      surfaceContainerHighest: ThemeDefine.kColorPage,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: ThemeDefine.kColorLine,
      hintColor: ThemeDefine.kColorText,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: ThemeDefine.kColorPage,
        foregroundColor: ThemeDefine.kColorTitle,
        centerTitle: false,
        titleSpacing: 15,
      ),
      cardTheme: CardThemeData(
        color: ThemeDefine.kColorCard,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        shadowColor: const Color(0x14201C27),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ThemeDefine.kColorCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ThemeDefine.kColorCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(
        color: ThemeDefine.kColorLine,
        space: 1,
        thickness: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: ThemeDefine.kColorCard,
        filled: true,
        labelStyle: const TextStyle(color: ThemeDefine.kColorText),
        floatingLabelStyle: const TextStyle(color: ThemeDefine.kColorPrimary),
        helperStyle: const TextStyle(color: ThemeDefine.kColorText),
        hintStyle: const TextStyle(color: ThemeDefine.kColorText),
        errorStyle: const TextStyle(color: ThemeDefine.kColorPrimary),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: ThemeDefine.kColorBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: ThemeDefine.kColorBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: ThemeDefine.kColorPrimary),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        iconColor: ThemeDefine.kColorTitle2,
        textColor: ThemeDefine.kColorTitle,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ThemeDefine.kColorDisable;
            }
            return ThemeDefine.kColorPrimary;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ThemeDefine.kColorPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ThemeDefine.kColorPrimary;
          }
          return ThemeDefine.kColorDisable;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ThemeDefine.kColorPrimary,
        strokeWidth: 2,
      ),
      iconTheme: const IconThemeData(color: ThemeDefine.kColorTitle),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ThemeDefine.kColorCard,
        indicatorColor: const Color(0xFFFFEBE8),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? ThemeDefine.kColorPrimary : ThemeDefine.kColorTitle2,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            height: 1.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? ThemeDefine.kColorPrimary : ThemeDefine.kColorTitle2,
          );
        }),
      ),
    );
  }
}
