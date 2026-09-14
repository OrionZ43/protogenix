import 'dart:io';

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static final bool _isDesktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static ThemeData dark({ColorScheme? colorScheme}) {
    final scheme = colorScheme ??
        ColorScheme.fromSeed(
          seedColor: AppColors.defaultSeed,
          brightness: Brightness.dark,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,

      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.white.withAlpha(12),
      splashColor: Colors.white.withAlpha(20),
      highlightColor: Colors.white.withAlpha(15),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withAlpha(25);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withAlpha(12);
            }
            return Colors.transparent;
          }),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: AppColors.glassSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.2),
      ),
      // Плашки. В M3 фон плашки по умолчанию светлый, а текст тёмный; где
      // задавали только тёмный фон, текст оставался тёмным — «Добавлено в…»
      // было не прочитать. На ПК плашка встаёт по центру над нижним плеером
      // (DesktopBottomPlayer — до 162 px), а не поверх него.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.glassDark,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        width: _isDesktop ? 460 : null,
        insetPadding:
            _isDesktop ? const EdgeInsets.fromLTRB(24, 10, 24, 176) : null,
      ),
      // Подсказки при наведении (ПК). В тёмной теме M3 они светло-серые с
      // тёмным текстом — единственное светлое пятно в приложении
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.glassDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      // Курсор и выделение текста — белые: фиолетовый цвет темы выбивался в
      // полях, где цвет обложки не задан
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Colors.white,
        selectionColor: Colors.white.withAlpha(60),
        selectionHandleColor: Colors.white70,
      ),
      // Запасной вид, если где-то появятся стандартные диалоги и текстовые
      // кнопки. Подтверждения — showGlassConfirm (core/widgets/glass_dialog.dart)
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.glassDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      textTheme: _buildTextTheme(scheme),
    );
  }

  static TextTheme _buildTextTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
        letterSpacing: -0.25,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
        letterSpacing: 0.15,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: scheme.onSurfaceVariant,
        letterSpacing: 0.25,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}
