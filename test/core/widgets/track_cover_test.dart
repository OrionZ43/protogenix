import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/widgets/track_cover.dart';

// Обложки импорт сохраняет 400×400. В списке они рисуются по 40–52 px,
// а декодировались целиком: 640 КБ в памяти на каждую (performance.md).

/// Картинка [size]×[size] в PNG — как файл обложки на диске.
Future<Uint8List> _png(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF7B5EA7),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Во что превращается провайдер после декодирования.
Future<ui.Image> _decode(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  provider.resolve(ImageConfiguration.empty).addListener(
        ImageStreamListener(
          (info, _) => completer.complete(info.image),
          onError: (e, _) => completer.completeError(e),
        ),
      );
  return completer.future;
}

void main() {
  testWidgets('обложка списка декодируется под плитку, а не в 400×400',
      (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('protogenix_cover_');
      final file = File('${dir.path}/cover.png');
      await file.writeAsBytes(await _png(400));

      late BuildContext context;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));

      PaintingBinding.instance.imageCache.clear();
      final full = await _decode(FileImage(file));
      expect(full.width, 400, reason: 'исходник декодируется как есть');

      PaintingBinding.instance.imageCache.clear();
      final thumb = await _decode(coverFromPath(context, file.path, 50));
      expect(thumb.width, 150, reason: 'плитка 50 px при dpr 3');
      expect(thumb.height, 150);

      final fullBytes = full.width * full.height * 4;
      final thumbBytes = thumb.width * thumb.height * 4;
      expect(thumbBytes * 7, lessThan(fullBytes),
          reason: 'памяти на обложку меньше минимум в 7 раз');

      await dir.delete(recursive: true);
    });
  });

  testWidgets('маленькая обложка не раздувается до размера плитки',
      (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('protogenix_cover_');
      final file = File('${dir.path}/small.png');
      await file.writeAsBytes(await _png(64));

      late BuildContext context;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));

      PaintingBinding.instance.imageCache.clear();
      final thumb = await _decode(coverFromPath(context, file.path, 50));
      expect(thumb.width, 64, reason: 'меньше плитки — декодируется как есть');

      await dir.delete(recursive: true);
    });
  });
}
