// lib/core/widgets/track_cover.dart
//
// Обложка трека, декодированная под тот размер, в котором её рисуют.
//
// Импорт сохраняет обложки 400×400 (`covers/<id>.jpg`). Flutter декодирует
// картинку целиком, независимо от размера на экране: 400×400 — это 640 КБ
// в памяти на каждую обложку. В списке медиатеки плитка 50×50, то есть
// в 64 раза меньше пикселей, чем декодируется.
//
// У кэша картинок Flutter предел 100 МБ, так что при паре сотен треков
// прокрутка списка выбивает из кэша уже декодированное и декодирует заново
// круг за кругом — отсюда рывки на телефонах с медленной памятью
// (`performance.md`). ResizeImage декодирует сразу в нужный размер: та же
// плитка при dpr 3 — 150×150, 90 КБ.
//
// [allowUpscaling] не включаем: если обложка меньше плитки (или плитка
// во весь экран), она декодируется как есть, без раздувания.

import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/cover_placeholder.dart';

/// Обложка из файла (или заглушка) под квадратную плитку [size] в логических
/// пикселях.
ImageProvider coverFromPath(
    BuildContext context, String? coverPath, double size) {
  // Без приведения ветки условие выводится в Object: AssetImage и FileImage —
  // разные реализации ImageProvider со своим типом ключа
  final ImageProvider source = coverPath == null
      ? kCoverPlaceholder
      : FileImage(File(coverPath)) as ImageProvider;
  return sizedCover(context, source, size);
}

/// Готовый ImageProvider (например, `TrackModel.coverImage`) под размер [size]
/// в логических пикселях.
ImageProvider sizedCover(
    BuildContext context, ImageProvider source, double size) {
  if (size <= 0 || !size.isFinite) return source;
  final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
  if (px <= 0) return source;
  return ResizeImage(
    source,
    width: px,
    height: px,
    policy: ResizeImagePolicy.fit,
  );
}
