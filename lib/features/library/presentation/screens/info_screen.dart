import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/widgets/z43_branding.dart';
import '../../../../core/widgets/neon_logo.dart';
import '../../../player/presentation/widgets/glass_card.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';

import 'dart:ui';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProtogenixBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: GlassCard(
              padding: const EdgeInsets.all(40),
              borderRadius: 32.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Логотип
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFCE93D8).withAlpha(60),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const NeonLogo(size: 140),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Protogenix',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'v1.0.0 — Плеер нового поколения',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Z43BrandingBadge(),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
              ),
              const Positioned(
                top: 16,
                left: 16,
                child: _CloseButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: Colors.white.withAlpha(217),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withAlpha(26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withAlpha(38)),
            ),
          ),
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
