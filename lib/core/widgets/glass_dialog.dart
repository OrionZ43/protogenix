// lib/core/widgets/glass_dialog.dart
//
// Подтверждение в стиле приложения: тёмное стекло, иконка в круге, кнопки-
// таблетки. Вместо стандартного AlertDialog: тот с кнопками-надписями
// выбивался из шторок и плашек. showGlassInfo — то же окно с одной кнопкой,
// для объяснений.

import 'package:flutter/material.dart';

import 'chip_button.dart';
import 'glass_panel.dart';

/// true — подтвердили; закрыли мимо или «Отмена» — false. [color] — иконка и
/// кнопка подтверждения; по умолчанию красный: подтверждают обычно удаление.
Future<bool> showGlassConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.delete_outline_rounded,
  Color color = Colors.redAccent,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withAlpha(120),
    builder: (_) => _GlassConfirm(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      color: color,
    ),
  );
  return confirmed ?? false;
}

/// То же окно, но с одной кнопкой: объяснение, а не выбор. [color] — иконка
/// и кнопка; для акцента передавать цвет обложки (paletteProvider).
Future<void> showGlassInfo(
  BuildContext context, {
  required String title,
  required String message,
  String buttonLabel = 'Понятно',
  IconData icon = Icons.info_outline_rounded,
  Color? color,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(120),
      builder: (_) => _GlassConfirm(
        title: title,
        message: message,
        confirmLabel: buttonLabel,
        icon: icon,
        color: color ?? Colors.white,
        withCancel: false,
      ),
    );

class _GlassConfirm extends StatelessWidget {
  const _GlassConfirm({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.icon,
    required this.color,
    this.withCancel = true,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final IconData icon;
  final Color color;
  final bool withCancel;

  @override
  Widget build(BuildContext context) {
    const buttonPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 13);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          // Material — ради стиля текста по умолчанию: без него у диалога
          // жёлтое подчёркивание
          child: Material(
            type: MaterialType.transparency,
            child: GlassPanel(
              borderRadius: 24,
              alpha: 200,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withAlpha(40),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Длинное объяснение (showGlassInfo) прокручивается: без
                  // Flexible оно вылезало за экран на невысоких окнах
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withAlpha(150),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (withCancel) ...[
                        Expanded(
                          child: ChipButton(
                            label: 'Отмена',
                            padding: buttonPadding,
                            onTap: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ChipButton(
                          label: confirmLabel,
                          accent: color,
                          padding: buttonPadding,
                          onTap: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
