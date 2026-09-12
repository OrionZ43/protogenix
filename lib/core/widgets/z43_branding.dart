// lib/core/widgets/z43_branding.dart
//
// Подпись Z43 Studios и ссылки на сайт, GitHub и Telegram — внизу страницы
// «Инфо».

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chip_button.dart';

class Z43BrandingBadge extends StatelessWidget {
  const Z43BrandingBadge({super.key});

  static const _links = [
    (
      label: 'Сайт',
      icon: Icons.public_rounded,
      url: 'https://z43-studios.vercel.app/',
    ),
    (
      label: 'GitHub',
      icon: Icons.code_rounded,
      url: 'https://github.com/OrionZ43/protogenix',
    ),
    (
      label: 'Telegram',
      icon: Icons.send_rounded,
      url: 'https://t.me/Orion_Z43',
    ),
  ];

  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Z43] Не удалось открыть $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final link in _links)
              ChipButton(
                label: link.label,
                icon: link.icon,
                onTap: () => _open(link.url),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'СДЕЛАНО С ❤ Z43 STUDIOS',
          style: TextStyle(
            color: Colors.white.withAlpha(90),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
