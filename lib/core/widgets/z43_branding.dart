import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class Z43BrandingBadge extends StatelessWidget {
  const Z43BrandingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          'СДЕЛАНО С ❤ Z43 STUDIOS',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LinkBtn(label: 'САЙТ', url: 'https://z43-studios.vercel.app/'),
            _Dot(),
            _LinkBtn(
                label: 'GITHUB', url: 'https://github.com/OrionZ43/protogenix'),
            _Dot(),
            _LinkBtn(label: 'TG', url: 'https://t.me/Orion_Z43'),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) =>
      const Text(' · ', style: TextStyle(color: Colors.white12, fontSize: 10));
}

class _LinkBtn extends StatelessWidget {
  const _LinkBtn({required this.label, required this.url});
  final String label;
  final String url;

  Future<void> _open() async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white24,
        ),
      ),
    );
  }
}
