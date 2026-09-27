import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/theme/app_colors.dart';

// Акцент — это цвет обложки, и он бывает каким угодно. Там, где им красят
// текст, иконку или рамку на тёмном фоне, он обязан оставаться читаемым
// (`AppColors.readableAccent`), иначе выделенный пункт выглядит бледнее
// невыделенного — те рисуются белым.

double lightnessOf(Color c) => HSLColor.fromColor(c).lightness;
double saturationOf(Color c) => HSLColor.fromColor(c).saturation;
double hueOf(Color c) => HSLColor.fromColor(c).hue;

void main() {
  test('тёмный цвет обложки поднимается до читаемого', () {
    // Палитра подкручивает primary до яркости не ниже 0.2 — вот такой случай
    const dark = Color(0xFF1B2A4A);
    final fixed = AppColors.readableAccent(dark);

    expect(lightnessOf(dark), lessThan(0.3), reason: 'исходный и правда тёмный');
    expect(lightnessOf(fixed), greaterThanOrEqualTo(0.5));
  });

  test('блёклый цвет становится заметным, а не серым пятном', () {
    const washedOut = Color(0xFF474448); // почти серый
    final fixed = AppColors.readableAccent(washedOut);

    expect(saturationOf(fixed), greaterThanOrEqualTo(0.3));
    expect(lightnessOf(fixed), greaterThanOrEqualTo(0.5));
  });

  test('оттенок не меняется — это по-прежнему цвет обложки', () {
    for (final colour in [
      const Color(0xFF1B2A4A), // синий
      const Color(0xFF3A1010), // красный
      const Color(0xFF12331A), // зелёный
    ]) {
      final fixed = AppColors.readableAccent(colour);
      expect(hueOf(fixed), closeTo(hueOf(colour), 1.0));
    }
  });

  test('уже яркий цвет не трогаем', () {
    for (final colour in [
      const Color(0xFFCE93D8), // AppColors.neonPurple
      const Color(0xFF80DEEA), // AppColors.neonCyan
      Colors.red, // кнопки удаления
    ]) {
      expect(AppColors.readableAccent(colour), colour);
    }
  });

  test('чёрный и белый не ломают разбор', () {
    final black = AppColors.readableAccent(const Color(0xFF000000));
    expect(lightnessOf(black), greaterThanOrEqualTo(0.5));
    expect(AppColors.readableAccent(const Color(0xFFFFFFFF)),
        const Color(0xFFFFFFFF));
  });
}
