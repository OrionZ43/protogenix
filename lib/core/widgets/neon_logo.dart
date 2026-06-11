import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class NeonLogo extends StatelessWidget {
  final double size;
  const NeonLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF80DEEA), Color(0xFFCE93D8)], // Циан к пурпурному
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: SvgPicture.asset(
        'assets/images/logo.svg',
        width: size,
        height: size,
      ),
    );
  }
}
