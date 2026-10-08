// lib/core/utils/frame_report.dart
//
// Сколько миллисекунд стоит кадр. Работает **только в профильной сборке**.
//
// Зачем это нужно отдельно от FPS. На хорошем телефоне приложение упирается
// в потолок частоты экрана, и тогда FPS не отвечает на главный вопрос —
// сколько запаса осталось. Пример: на Pixel 7 экран караоке держит ровно
// 60 кадров в секунду, и что ни отключай (размытия, свечение букв, фон,
// караоке по слогам), цифра не меняется. А на слабом телефоне тот же кадр
// не укладывается в бюджет, и человек видит 15 кадров вместо 60.
//
// Поэтому меряем не FPS, а **время кадра**: отдельно работу Dart (build и
// layout, поток UI) и отрисовку (raster). Эти миллисекунды можно переносить
// на другое железо: если на Pixel 7 растр занимает 6 мс, то на телефоне
// втрое медленнее это уже 18 мс — мимо бюджета 60 кадров (16,7 мс).
//
// Как пользоваться:
//   flutter build apk --profile --target-platform android-arm64
//   adb logcat -s flutter | findstr "[Кадры]"
//
// В релизной сборке ничего этого нет: `kProfileMode` — константа времени
// компиляции, и весь код выкидывается.

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Через сколько кадров печатать сводку.
const _kBatch = 120;

bool _started = false;

/// Включить отчёт о кадрах. В релизе не делает ничего.
void startFrameReport() {
  if (!kProfileMode || _started) return;
  _started = true;

  final ui = <int>[];
  final raster = <int>[];
  final total = <int>[];

  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      ui.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
      total.add(t.totalSpan.inMicroseconds);
    }
    if (ui.length < _kBatch) return;

    String stat(List<int> values) {
      final sorted = [...values]..sort();
      double ms(int micros) => micros / 1000;
      final avg = values.reduce((a, b) => a + b) / values.length;
      final p50 = sorted[sorted.length ~/ 2];
      final p95 = sorted[(sorted.length * 0.95).floor()];
      return '${ms(avg.round()).toStringAsFixed(1)} сред / '
          '${ms(p50).toStringAsFixed(1)} сер / '
          '${ms(p95).toStringAsFixed(1)} p95';
    }

    // ignore: avoid_print
    print('[Кадры] ${ui.length} шт · '
        'UI ${stat(ui)} · растр ${stat(raster)} · всего ${stat(total)}');
    ui.clear();
    raster.clear();
    total.clear();
  });
}
