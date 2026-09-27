import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/queue_shuffle.dart';

// Вопрос Orion: не получается ли каждый раз один и тот же порядок.
// shuffleAround без явного Random отдаёт список в List.shuffle(null), а тот
// сам создаёт новый Random() — то есть порядок каждый раз свой.

void main() {
  test('каждое включение перемешивания даёт свой порядок', () {
    // 18 треков — как у пользователя, на которого ссылался Orion
    final queue = [for (var i = 0; i < 18; i++) 'track$i'];

    final orders = <String>{};
    for (var attempt = 0; attempt < 20; attempt++) {
      final shuffled = shuffleAround(queue, 0);
      expect(shuffled.first, 'track0', reason: 'текущий трек остаётся первым');
      expect(shuffled.toSet(), queue.toSet(), reason: 'треки не теряются');
      expect(shuffled.length, queue.length);
      orders.add(shuffled.join(','));
    }

    // Совпасть дважды подряд у 17 элементов — 1 к 17!, то есть никогда
    expect(orders.length, greaterThan(15),
        reason: 'порядок должен меняться от раза к разу');
  });

  test('перемешивание вокруг текущего трека, а не только первого', () {
    final queue = [for (var i = 0; i < 18; i++) 'track$i'];
    final shuffled = shuffleAround(queue, 7);
    expect(shuffled.first, 'track7');
    expect(shuffled.toSet(), queue.toSet());
  });
}
