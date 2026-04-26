// lib/core/utils/haptic_patterns.dart
//
// HapticPatterns v3 — «Нарисованная» вибрация для Protogenix.
//
// Платформа предоставляет три силы: light / medium / heavy.
// Мы комбинируем их во времени как ноты в ритмическом рисунке.
//
// Принцип дизайна:
//   ▸ Play/Pause  — «сердцебиение»: дум-дум с мягким эхо
//   ▸ Next        — «пуля вперёд»: нарастающий дублет + мощный финал
//   ▸ Previous    — «откат назад»: тяжёлый старт, быстрое затухание
//   ▸ Shuffle ON  — «перемешивание карт»: пять хаотичных тиков
//   ▸ Shuffle OFF — «стоп»: один точный клик
//   ▸ Repeat      — «замок щёлкнул»: medium + тихое эхо
//   ▸ Seek        — «tick часов»: selectionClick (sync, без await)
//   ▸ Favorite ♥  — «взрыв любви»: crescendo light→medium→heavy + послесвечение
//   ▸ Error       — «отказ»: три удара с нарастанием тревоги
//   ▸ Long press  — «подтверждение»: тяжёлый + двойное эхо

import 'package:flutter/services.dart';

// Внутренний тип удара
enum _H { l, m, h, s } // light / medium / heavy / selectionClick

class HapticPatterns {
  HapticPatterns._();

  // ── Исполнитель последовательности ──────────────────────────────────────
  // delayMs — пауза ПЕРЕД этим ударом (первый удар = 0, всегда мгновенный)

  static Future<void> _play(List<({_H h, int delayMs})> score) async {
    for (var i = 0; i < score.length; i++) {
      final beat = score[i];
      if (i > 0 && beat.delayMs > 0) {
        await Future.delayed(Duration(milliseconds: beat.delayMs));
      }
      _hit(beat.h);
    }
  }

  static void _hit(_H h) {
    switch (h) {
      case _H.l:
        HapticFeedback.lightImpact();
      case _H.m:
        HapticFeedback.mediumImpact();
      case _H.h:
        HapticFeedback.heavyImpact();
      case _H.s:
        HapticFeedback.selectionClick();
    }
  }

  // ── PLAY / PAUSE — «сердцебиение» duum-dum ──────────────────────────────
  // Рисунок: тяжёлый → (60ms) → лёгкий → (110ms) → тихое эхо
  static Future<void> playPause() => _play([
        (h: _H.h, delayMs: 0),
        (h: _H.l, delayMs: 60),
        (h: _H.s, delayMs: 110),
      ]);

  // ── NEXT — «пуля вперёд» ─────────────────────────────────────────────────
  // Рисунок: лёгкий → (45ms) → средний → (55ms) → тяжёлый
  // Ощущение нарастания скорости (вжух →→→)
  static Future<void> next() => _play([
        (h: _H.l, delayMs: 0),
        (h: _H.m, delayMs: 45),
        (h: _H.h, delayMs: 55),
      ]);

  // ── PREVIOUS — «откат назад» ──────────────────────────────────────────────
  // Рисунок: тяжёлый → (50ms) → средний → (40ms) → лёгкий
  // Зеркало next: затухание вместо нарастания
  static Future<void> previous() => _play([
        (h: _H.h, delayMs: 0),
        (h: _H.m, delayMs: 50),
        (h: _H.l, delayMs: 40),
      ]);

  // ── SHUFFLE ON — «перемешивание карт» ────────────────────────────────────
  // Рисунок: 5 тиков с уменьшающимися паузами (ускорение = хаос)
  static Future<void> shuffleOn() => _play([
        (h: _H.s, delayMs: 0),
        (h: _H.s, delayMs: 80),
        (h: _H.s, delayMs: 60),
        (h: _H.l, delayMs: 45),
        (h: _H.m, delayMs: 35),
      ]);

  // ── SHUFFLE OFF — «стоп, фиксация» ───────────────────────────────────────
  // Один точный средний удар — ощущение "поставили на место"
  static Future<void> shuffleOff() async => HapticFeedback.mediumImpact();

  // ── REPEAT — «замок щёлкнул» ─────────────────────────────────────────────
  // medium + тихое эхо через 90ms
  static Future<void> repeat() => _play([
        (h: _H.m, delayMs: 0),
        (h: _H.s, delayMs: 90),
      ]);

  // ── SEEK — «tick часов» (синхронный, вызывается при каждом шаге) ─────────
  static void seek() => HapticFeedback.selectionClick();

  // ── FAVORITE ♥ — «взрыв любви» ───────────────────────────────────────────
  // Crescendo: l → m → h → (послесвечение двумя тиками)
  static Future<void> favorite() => _play([
        (h: _H.l, delayMs: 0),
        (h: _H.m, delayMs: 80),
        (h: _H.h, delayMs: 100),
        (h: _H.s, delayMs: 120),
        (h: _H.s, delayMs: 80),
      ]);

  // ── ERROR — «отказ системы» ──────────────────────────────────────────────
  // Три удара с нарастанием: l → h → h (пауза увеличивается → тревога растёт)
  static Future<void> error() => _play([
        (h: _H.l, delayMs: 0),
        (h: _H.h, delayMs: 100),
        (h: _H.h, delayMs: 130),
      ]);

  // ── LONG PRESS — «подтверждение действия» ────────────────────────────────
  // Тяжёлый удар + двойное эхо = "принято"
  static Future<void> longPress() => _play([
        (h: _H.h, delayMs: 0),
        (h: _H.m, delayMs: 100),
        (h: _H.l, delayMs: 70),
      ]);

  // ── LYRICS LINE CHANGE — «смена строки в караоке» ────────────────────────
  // Едва ощутимый двойной тик — ритмично, ненавязчиво
  static Future<void> lyricsLine() => _play([
        (h: _H.s, delayMs: 0),
        (h: _H.s, delayMs: 55),
      ]);
}
