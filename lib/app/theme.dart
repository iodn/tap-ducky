import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light({ColorScheme? dynamicScheme}) {
    final base = dynamicScheme != null
        ? ThemeData(useMaterial3: true, colorScheme: dynamicScheme)
        : ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF6A5CFF),
            brightness: Brightness.light,
          );
    final cs = base.colorScheme;
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(color: cs.outlineVariant.withOpacity(0.5), thickness: 1),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(borderSide: BorderSide(color: cs.outline)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.primary, width: 2)),
      ),
      cardTheme: base.cardTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(surfaceTintColor: Colors.transparent),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
      ),
    );
  }

  static ThemeData dark({ColorScheme? dynamicScheme}) {
    final base = dynamicScheme != null
        ? ThemeData(useMaterial3: true, colorScheme: dynamicScheme)
        : ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF6A5CFF),
            brightness: Brightness.dark,
          );
    final cs = base.colorScheme;
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(color: cs.outlineVariant.withOpacity(0.5), thickness: 1),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(borderSide: BorderSide(color: cs.outline)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.primary, width: 2)),
      ),
      cardTheme: base.cardTheme.copyWith(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(surfaceTintColor: Colors.transparent),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
      ),
    );
  }
}

extension ColorSchemeExtension on ColorScheme {
  Color get success => brightness == Brightness.light
      ? const Color(0xFF2E7D32) 
      : const Color(0xFF66BB6A);

  Color get warning => brightness == Brightness.light
      ? const Color(0xFFEF6C00)  
      : const Color(0xFFFFB74D); 
}
