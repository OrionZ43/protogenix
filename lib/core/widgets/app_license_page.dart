// lib/core/widgets/app_license_page.dart
//
// Лицензии открытого ПО (кнопка на странице «Инфо»). Встроенный LicensePage
// берёт тему приложения, а в ней фон экранов и AppBar прозрачные: так задумано
// под анимированный фон (AppTheme.dark). Своего фона у LicensePage нет, поэтому
// страница просвечивала, а текст заезжал под заголовок. Здесь для неё —
// непрозрачная тема в цветах приложения.

import 'package:flutter/material.dart';

import 'neon_logo.dart';

const _background = Color(0xFF080810);
const _surface = Color(0xFF12121C);

void showAppLicenses(BuildContext context, {String? version}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => AppLicensePage(version: version)),
  );
}

class AppLicensePage extends StatelessWidget {
  const AppLicensePage({super.key, this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: _background,
        colorScheme: theme.colorScheme.copyWith(surface: _background),
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: _background,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: theme.cardTheme.copyWith(
          color: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withAlpha(20)),
          ),
        ),
      ),
      child: LicensePage(
        applicationName: 'Protogenix',
        applicationVersion: version == null ? null : 'v$version',
        applicationIcon: const Padding(
          padding: EdgeInsets.all(12),
          child: NeonLogo(size: 64),
        ),
        applicationLegalese: 'Z43 Studios',
      ),
    );
  }
}
