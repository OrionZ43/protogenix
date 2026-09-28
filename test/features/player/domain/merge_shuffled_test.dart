import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/queue_shuffle.dart';

// Отзыв Elian: перемешивание «несколько раз может выдать один и тот же трек».
// Рандом честный, а повторы брались от того, что любое обновление очереди
// перемешивало её заново (`mergeShuffled`).

({List<String> queue, int index}) merge(
  List<String> shuffled,
  List<String> incoming,
  int currentIndex, [
  int seed = 1,
]) =>
    mergeShuffled(
      shuffled: shuffled,
      incoming: incoming,
      currentIndex: currentIndex,
      key: (s) => s,
      random: Random(seed),
    );

void main() {
  test('тот же набор — порядок не меняется вообще', () {
    final result = merge(['c', 'a', 'd', 'b'], ['a', 'b', 'c', 'd'], 1);
    expect(result.queue, ['c', 'a', 'd', 'b']);
    expect(result.index, 1, reason: 'играющий трек остался на своём месте');
  });

  test('скачали новый трек — сыгравшее не сдвигается и не повторяется', () {
    // Играем 'd' (третий), значит 'c' и 'a' уже сыграли
    final result = merge(['c', 'a', 'd', 'b'], ['a', 'b', 'c', 'd', 'new'], 2);

    expect(result.queue.take(3), ['c', 'a', 'd'],
        reason: 'всё до играющего включительно осталось на месте');
    expect(result.index, 2);
    expect(result.queue.length, 5);
    expect(result.queue.indexOf('new'), greaterThan(2),
        reason: 'новый трек попал в ещё не сыгранную часть');
  });

  test('несколько новых треков — все после текущего', () {
    final result =
        merge(['c', 'a', 'd', 'b'], ['a', 'b', 'c', 'd', 'x', 'y', 'z'], 1);
    expect(result.queue.length, 7);
    for (final track in ['x', 'y', 'z']) {
      expect(result.queue.indexOf(track), greaterThan(result.index),
          reason: '$track должен быть впереди');
    }
    expect(result.queue[result.index], 'a', reason: 'играет тот же трек');
  });

  test('трек удалили из медиатеки — выпадает из очереди', () {
    final result = merge(['c', 'a', 'd', 'b'], ['a', 'b', 'd'], 2);
    expect(result.queue, ['a', 'd', 'b']);
    expect(result.queue[result.index], 'd', reason: 'играющий не потерялся');
  });

  test('удалили как раз тот, что играет', () {
    final result = merge(['c', 'a', 'd', 'b'], ['a', 'c', 'b'], 2);
    expect(result.queue, ['c', 'a', 'b']);
    expect(result.index, inInclusiveRange(0, 2));
  });

  test('состав не теряется и не задваивается', () {
    final result = merge(['c', 'a', 'd', 'b'], ['a', 'b', 'c', 'd', 'e'], 0);
    expect(result.queue.toSet(), {'a', 'b', 'c', 'd', 'e'});
    expect(result.queue.length, 5, reason: 'без дублей');
  });

  test('пустые очереди не ломают разбор', () {
    expect(merge([], ['a', 'b'], 0).queue, ['a', 'b']);
    expect(merge(['a'], [], 0).queue, isEmpty);
  });

  test('новые треки встают в разные места, а не всегда в одно', () {
    final places = <int>{};
    for (var seed = 0; seed < 12; seed++) {
      final result =
          merge(['a', 'b', 'c', 'd', 'e'], ['a', 'b', 'c', 'd', 'e', 'n'], 0, seed);
      places.add(result.queue.indexOf('n'));
    }
    expect(places.length, greaterThan(1), reason: 'место правда случайное');
  });
}
