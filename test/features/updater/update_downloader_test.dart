import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/features/updater/update_downloader.dart';
import 'package:protogenix/features/updater/update_installer.dart';
import 'package:protogenix/features/updater/update_manifest.dart';

void main() {
  late HttpServer server;
  late Directory tmp;
  late Uint8List payload;
  late List<String> requests;
  late List<String?> ranges;
  late bool honorRange;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('protogenix_update_');
    payload = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    requests = [];
    ranges = [];
    honorRange = true;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      requests.add(request.uri.path);
      ranges.add(range);

      switch (request.uri.path) {
        case '/protogenix.bin':
          if (honorRange && range != null) {
            final start = int.parse(
                RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
            response.statusCode = HttpStatus.partialContent;
            response.headers.set(HttpHeaders.contentRangeHeader,
                'bytes $start-${payload.length - 1}/${payload.length}');
            response.add(payload.sublist(start));
          } else {
            response.add(payload);
          }
        case '/corrupt/protogenix.bin':
          response.add(Uint8List.fromList(payload)..[0] ^= 0xff);
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  UpdateAsset asset(List<String> paths) => UpdateAsset(
        urls: [
          for (final path in paths)
            Uri.parse('http://127.0.0.1:${server.port}$path'),
        ],
        size: payload.length,
        sha256: sha256.convert(payload).toString(),
      );

  UpdateDownloader downloader() => UpdateDownloader(directory: tmp);

  File partOf(UpdateAsset a) => File(
      p.join(tmp.path, '${a.fileName}.${a.sha256.substring(0, 12)}.part'));

  test('скачивает файл и сверяет SHA-256', () async {
    final progress = <double>[];
    final file = await downloader()
        .download(asset(['/protogenix.bin']), onProgress: progress.add);

    expect(await file.readAsBytes(), payload);
    expect(p.basename(file.path), 'protogenix.bin');
    expect(File('${file.path}.part').existsSync(), isFalse);
    expect(progress.last, 1.0);
  });

  test('докачивает с места обрыва', () async {
    final a = asset(['/protogenix.bin']);
    await partOf(a).writeAsBytes(payload.sublist(0, 100000));

    final file = await downloader().download(a);

    expect(ranges.single, 'bytes=100000-');
    expect(await file.readAsBytes(), payload);
  });

  test('кусок другой версии не продолжается, а удаляется', () async {
    final a = asset(['/protogenix.bin']);
    // Старое имя куска (до 1.0.1) и кусок другой версии с новой пометкой
    final legacy = File(p.join(tmp.path, '${a.fileName}.part'));
    final otherVersion =
        File(p.join(tmp.path, '${a.fileName}.0123456789ab.part'));
    await legacy.writeAsBytes(List.filled(100000, 7));
    await otherVersion.writeAsBytes(List.filled(50000, 9));

    final file = await downloader().download(a);

    expect(ranges.single, isNull, reason: 'качать с нуля, без Range');
    expect(await file.readAsBytes(), payload);
    expect(legacy.existsSync(), isFalse);
    expect(otherVersion.existsSync(), isFalse);
  });

  test('если сервер игнорирует Range — качает заново', () async {
    honorRange = false;
    final a = asset(['/protogenix.bin']);
    await partOf(a).writeAsBytes(payload.sublist(0, 100000));

    final file = await downloader().download(a);

    expect(await file.readAsBytes(), payload);
  });

  test('при 404 переходит на следующий адрес', () async {
    final file = await downloader()
        .download(asset(['/missing/protogenix.bin', '/protogenix.bin']));

    expect(requests, ['/missing/protogenix.bin', '/protogenix.bin']);
    expect(await file.readAsBytes(), payload);
  });

  test('при несовпадении SHA-256 пробует следующий адрес', () async {
    final file = await downloader()
        .download(asset(['/corrupt/protogenix.bin', '/protogenix.bin']));

    expect(await file.readAsBytes(), payload);
  });

  test('если все адреса отказали — UpdateDownloadException', () async {
    await expectLater(
      downloader().download(asset(['/missing/protogenix.bin'])),
      throwsA(isA<UpdateDownloadException>()),
    );
  });

  test('уже скачанный и проверенный файл повторно не качается', () async {
    final a = asset(['/protogenix.bin']);
    await downloader().download(a);
    requests.clear();

    await downloader().download(a);

    expect(requests, isEmpty);
  });

  test('ключи тихой установки Inno Setup', () {
    expect(
      UpdateInstaller.windowsInstallerArguments(r'C:\Temp\update.log'),
      [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/update=1',
        r'/LOG=C:\Temp\update.log',
      ],
    );
  });
}
