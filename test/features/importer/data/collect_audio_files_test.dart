import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/features/importer/data/local_tags.dart';

void main() {
  test('папки целиком, регистр не важен, остальное мимо', () async {
    final tmp = await Directory.systemTemp.createTemp('protogenix_drop_');
    addTearDown(() => tmp.delete(recursive: true));
    File touch(String rel) =>
        File(p.join(tmp.path, rel))..createSync(recursive: true);

    touch('Альбом/01 - Интро.MP3');
    touch('Альбом/CD2/02.flac');
    touch('Альбом/cover.jpg');
    final single = touch('single.m4a');
    final notes = touch('notes.txt');

    final files = await collectAudioFiles(
        [p.join(tmp.path, 'Альбом'), single.path, notes.path]);

    expect(files.map(p.basename).toSet(),
        {'01 - Интро.MP3', '02.flac', 'single.m4a'});
  });
}
