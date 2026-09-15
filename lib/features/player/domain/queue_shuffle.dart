// lib/features/player/domain/queue_shuffle.dart
//
// Перемешивание очереди делает приложение, а не плеер. У just_audio оно не
// включается никогда: на Windows just_audio_media_kit передаёт его в mpv
// командой playlist-shuffle, mpv физически переставляет свой плейлист, и
// индекс текущего трека приходит уже в перемешанном порядке — звук играет
// один трек, а название и обложка берутся от другого (known-issues.md).
//
// Поэтому при включении очередь переставляется здесь: текущий трек — первым,
// остальные вразброс; при выключении возвращается исходный порядок.

import 'dart:math';

/// [queue], где трек [currentIndex] первый, а остальные в случайном порядке.
List<T> shuffleAround<T>(List<T> queue, int currentIndex, [Random? random]) {
  if (queue.isEmpty) return [];
  final index = currentIndex.clamp(0, queue.length - 1);
  final rest = [
    for (var i = 0; i < queue.length; i++)
      if (i != index) queue[i],
  ]..shuffle(random);
  return [queue[index], ...rest];
}

/// Исходный порядок [original] для перемешанной очереди [shuffled] и место в
/// нём текущего трека [current].
///
/// Треки, которых в перемешанной очереди уже нет, не возвращаются; добавленные,
/// пока она была перемешана, остаются — в конце, в том порядке, в каком
/// стояли. [key] — чем сравнивать треки (id): после перезагрузок экземпляры
/// бывают новыми.
({List<T> queue, int index}) unshuffle<T>({
  required List<T> original,
  required List<T> shuffled,
  required T current,
  required Object? Function(T) key,
}) {
  // Экземпляры из перемешанной очереди, которые ещё не разложены, — по ключу
  final pending = <Object?, List<T>>{};
  for (final item in shuffled) {
    pending.putIfAbsent(key(item), () => []).add(item);
  }

  final restored = <T>[];
  for (final item in original) {
    final same = pending[key(item)];
    if (same != null && same.isNotEmpty) restored.add(same.removeAt(0));
  }
  // Добавленные в перемешанную очередь — в конец, в её порядке
  for (final item in shuffled) {
    final same = pending[key(item)];
    if (same == null) continue;
    final i = same.indexWhere((x) => identical(x, item));
    if (i >= 0) restored.add(same.removeAt(i));
  }

  var index = restored.indexWhere((x) => identical(x, current));
  if (index < 0) index = restored.indexWhere((x) => key(x) == key(current));
  return (queue: restored, index: index < 0 ? 0 : index);
}
