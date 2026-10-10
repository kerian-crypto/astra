import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Identité visuelle d'Astra Client : claire, professionnelle et sereine,
/// volontairement distincte d'Astra Hub (sombre, violet) pour que le client
/// reconnaisse immédiatement son espace (§53). Mode sombre suivant le système.
abstract final class ClientColors {
  static const ink = Color(0xFF0B2239); // bleu nuit : titres, marque
  static const teal = Color(0xFF0E7C86); // action principale
  static const tealSoft = Color(0xFFE3F3F4);
  static const amber = Color(0xFFE59A2F); // « à faire »
  static const amberSoft = Color(0xFFFDF1DF);
  static const success = Color(0xFF1E9E6A);
  static const successSoft = Color(0xFFE3F5EC);
  static const danger = Color(0xFFD14343);
  static const dangerSoft = Color(0xFFFBE7E7);
  static const info = Color(0xFF3567D6);
  static const infoSoft = Color(0xFFE6EDFB);
  static const neutralSoft = Color(0xFFEDF1F5);

  static const canvas = Color(0xFFF4F6F9);
  static const surface = Colors.white;
  static const text = Color(0xFF0F1B2A);
  static const textMuted = Color(0xFF5B6B7F);
  static const line = Color(0xFFE2E8F0);

  static const darkCanvas = Color(0xFF0B1219);
  static const darkSurface = Color(0xFF131D27);
  static const darkSurfaceHigh = Color(0xFF1B2733);
  static const darkLine = Color(0xFF243241);
  static const darkTeal = Color(0xFF4FC3CC);
}

/// Espacements (grille de 4).
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class ClientTheme {
  static const radius = 16.0;
  static const radiusSmall = 10.0;

  static ThemeData get light => _build(
    Brightness.light,
    const ColorScheme.light(
      primary: ClientColors.teal,
      onPrimary: Colors.white,
      primaryContainer: ClientColors.tealSoft,
      onPrimaryContainer: ClientColors.ink,
      secondary: ClientColors.ink,
      onSecondary: Colors.white,
      // Boutons « tonals » (Ouvrir, Télécharger…) : sarcelle douce.
      secondaryContainer: ClientColors.tealSoft,
      onSecondaryContainer: ClientColors.ink,
      tertiary: ClientColors.amber,
      tertiaryContainer: ClientColors.amberSoft,
      error: ClientColors.danger,
      errorContainer: ClientColors.dangerSoft,
      surface: ClientColors.surface,
      onSurface: ClientColors.text,
      onSurfaceVariant: ClientColors.textMuted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF8FAFC),
      surfaceContainer: ClientColors.neutralSoft,
      surfaceContainerHigh: Color(0xFFE7ECF2),
      outline: Color(0xFFCBD5E1),
      outlineVariant: ClientColors.line,
    ),
    canvas: ClientColors.canvas,
  );

  static ThemeData get dark => _build(
    Brightness.dark,
    const ColorScheme.dark(
      primary: ClientColors.darkTeal,
      onPrimary: Color(0xFF00363B),
      primaryContainer: Color(0xFF0F3E44),
      onPrimaryContainer: Color(0xFFCDEFF1),
      secondary: Color(0xFFB9CCE0),
      onSecondary: ClientColors.ink,
      secondaryContainer: Color(0xFF0F3E44),
      onSecondaryContainer: Color(0xFFCDEFF1),
      tertiary: Color(0xFFF2B65F),
      tertiaryContainer: Color(0xFF3D2C12),
      error: Color(0xFFF08080),
      errorContainer: Color(0xFF3F1D1D),
      surface: ClientColors.darkSurface,
      onSurface: Color(0xFFE6EDF4),
      onSurfaceVariant: Color(0xFF93A4B7),
      surfaceContainerLowest: ClientColors.darkCanvas,
      surfaceContainerLow: Color(0xFF111A23),
      surfaceContainer: ClientColors.darkSurfaceHigh,
      surfaceContainerHigh: Color(0xFF22303E),
      outline: Color(0xFF3A4B5D),
      outlineVariant: ClientColors.darkLine,
    ),
    canvas: ClientColors.darkCanvas,
  );

  static ThemeData _build(Brightness brightness, ColorScheme scheme, {required Color canvas}) {
    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSmall),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: rounded.copyWith(side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedLabelTextStyle: text.labelLarge?.copyWith(color: scheme.primary),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(borderSide: BorderSide(color: scheme.primary, width: 2)),
        errorBorder: field.copyWith(borderSide: BorderSide(color: scheme.error)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        iconColor: scheme.onSurfaceVariant,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainer,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Ton sémantique d'un statut (pastilles, icônes, actions).
enum Tone { neutral, info, success, warning, danger, brand }

extension ToneColors on Tone {
  Color foreground(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return switch (this) {
      Tone.neutral => scheme.onSurfaceVariant,
      Tone.info => dark ? const Color(0xFF8DB0F5) : ClientColors.info,
      Tone.success => dark ? const Color(0xFF6FD3A6) : ClientColors.success,
      Tone.warning => dark ? const Color(0xFFF2B65F) : const Color(0xFFB86E0B),
      Tone.danger => scheme.error,
      Tone.brand => scheme.primary,
    };
  }

  Color background(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    if (dark) return foreground(scheme).withValues(alpha: 0.14);
    return switch (this) {
      Tone.neutral => ClientColors.neutralSoft,
      Tone.info => ClientColors.infoSoft,
      Tone.success => ClientColors.successSoft,
      Tone.warning => ClientColors.amberSoft,
      Tone.danger => ClientColors.dangerSoft,
      Tone.brand => ClientColors.tealSoft,
    };
  }
}
