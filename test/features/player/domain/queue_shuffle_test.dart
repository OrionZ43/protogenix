import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/queue_shuffle.dart';

void main() {
  const tracks = ['a', 'b', 'c', 'd', 'e', 'f'];
  Object? byValue(String t) => t;

  test('текущий трек — первым, остальные те же', () {
    final shuffled = shuffleAround(tracks, 2, Random(1));
    expect(shuffled.first, 'c');
    expect(shuffled.length, tracks.length);
    expect(shuffled.toSet(), tracks.toSet());
  });

  test('пустая очередь и очередь из одного трека', () {
    expect(shuffleAround(<String>[], 0), isEmpty);
    expect(shuffleAround(['a'], 0), ['a']);
  });

  test('выключение возвращает исходный порядок и место текущего', () {
    final shuffled = shuffleAround(tracks, 2, Random(7));
    // Играет уже третий трек перемешанной очереди
    final current = shuffled[2];
    final restored = unshuffle(
        original: tracks, shuffled: shuffled, current: current, key: byValue);
    expect(restored.queue, tracks);
    expect(restored.index, tracks.indexOf(current));
  });

  test('добавленное в перемешанную очередь остаётся — в конце', () {
    final shuffled = [...shuffleAround(tracks, 0, Random(3))]
      ..insert(1, 'x')
      ..add('y');
    final restored = unshuffle(
        original: tracks, shuffled: shuffled, current: 'x', key: byValue);
    expect(restored.queue, [...tracks, 'x', 'y']);
    expect(restored.index, 6);
  });

  test('убранные треки не возвращаются, повторы не теряются', () {
    final restored = unshuffle(
      original: tracks,
      shuffled: ['c', 'a', 'a', 'e'],
      current: 'e',
      key: byValue,
    );
    expect(restored.queue, ['a', 'c', 'e', 'a']);
    expect(restored.index, 2);
  });
}
