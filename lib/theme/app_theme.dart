import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.page,
    required this.surface,
    required this.raisedSurface,
    required this.navigation,
    required this.border,
    required this.iconSurface,
    required this.chartGrid,
    required this.expense,
  });

  final Color page;
  final Color surface;
  final Color raisedSurface;
  final Color navigation;
  final Color border;
  final Color iconSurface;
  final Color chartGrid;
  final Color expense;

  static const light = AppPalette(
    page: Color(0xFFF5F8F5),
    surface: Color(0xFFFFFFFF),
    raisedSurface: Color(0xFFE7F3EB),
    navigation: Color(0xFFFBFDFC),
    border: Color(0xFFDCE7DF),
    iconSurface: Color(0xFFE7F3EB),
    chartGrid: Color(0xFFD8E5DC),
    expense: Color(0xFFE92732),
  );

  static const dark = AppPalette(
    page: Color(0xFF121713),
    surface: Color(0xFF1D241F),
    raisedSurface: Color(0xFF283329),
    navigation: Color(0xFF171E19),
    border: Color(0xFF4F6F3C),
    iconSurface: Color(0xFF283329),
    chartGrid: Color(0xFF364338),
    expense: Color(0xFFFF7777),
  );

  @override
  AppPalette copyWith({
    Color? page,
    Color? surface,
    Color? raisedSurface,
    Color? navigation,
    Color? border,
    Color? iconSurface,
    Color? chartGrid,
    Color? expense,
  }) => AppPalette(
    page: page ?? this.page,
    surface: surface ?? this.surface,
    raisedSurface: raisedSurface ?? this.raisedSurface,
    navigation: navigation ?? this.navigation,
    border: border ?? this.border,
    iconSurface: iconSurface ?? this.iconSurface,
    chartGrid: chartGrid ?? this.chartGrid,
    expense: expense ?? this.expense,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raisedSurface: Color.lerp(raisedSurface, other.raisedSurface, t)!,
      navigation: Color.lerp(navigation, other.navigation, t)!,
      border: Color.lerp(border, other.border, t)!,
      iconSurface: Color.lerp(iconSurface, other.iconSurface, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
    );
  }
}

class AppTheme {
  static const _lightGreen = Color(0xFF087F5B);
  static const _darkGreen = Color(0xFF087F5B);
  static const _nightGreen = Color(0xFF64D6A5);
  static const _nightOnGreen = Color(0xFF073B2A);

  static ThemeData light() => _build(
    brightness: Brightness.light,
    palette: AppPalette.light,
    seed: _lightGreen,
    primary: _darkGreen,
    onPrimary: Colors.white,
    text: const Color(0xFF20251C),
    secondaryText: const Color(0xFF626A5D),
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    palette: AppPalette.dark,
    seed: _nightGreen,
    primary: _nightGreen,
    onPrimary: _nightOnGreen,
    text: const Color(0xFFE7EEE7),
    secondaryText: const Color(0xFFB2BDB3),
  );

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
    required Color seed,
    required Color primary,
    required Color onPrimary,
    required Color text,
    required Color secondaryText,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      surface: palette.page,
      error: palette.expense,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.page,
      extensions: [palette],
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.page,
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: primary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.border),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.navigation,
        indicatorColor: palette.raisedSurface,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : secondaryText,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? Colors.white.withValues(alpha: .64)
            : palette.surface,
        labelStyle: TextStyle(color: secondaryText),
        hintStyle: TextStyle(color: secondaryText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? palette.raisedSurface
            : const Color(0xFF30352F),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: palette.surface,
        headerBackgroundColor: primary,
        headerForegroundColor: onPrimary,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get appPalette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}
