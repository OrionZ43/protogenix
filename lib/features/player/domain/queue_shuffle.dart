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

/// Обновить перемешанную очередь новым набором треков, **не перемешивая
/// заново**.
///
/// Зачем. Отзыв Elian (2026-09-27): «перемешивание работает на простом
/// рандоме, несколько раз может выдать один и тот же трек». Рандом на самом
/// деле честный — [shuffleAround] даёт перестановку, внутри одного прохода
/// повторов быть не может. Повторы брались с другой стороны: **любое
/// обновление очереди перемешивало её заново**. Скачался трек — медиатека
/// перечитывается (`reloadFromLibrary`), очередь собирается снова, порядок
/// новый, и уже сыгравшее снова оказывается впереди.
///
/// Что делает эта функция:
///   • треки, которые уже есть в очереди, остаются **на своих местах** —
///     значит, проход по очереди не начинается заново;
///   • исчезнувшие (удалили из медиатеки) выпадают;
///   • новые вставляются вразброс, но **только после текущего трека** —
///     чтобы они прозвучали в этом же проходе и при этом не сдвинули то,
///     что уже сыграно.
///
/// [shuffled] — очередь как она играет сейчас, [incoming] — новый набор
/// (в своём, неперемешанном порядке), [currentIndex] — где сейчас играем.
/// [key] — чем сравнивать треки (id): после перезагрузок экземпляры новые,
/// поэтому берём их из [incoming], а порядок — из [shuffled].
({List<T> queue, int index}) mergeShuffled<T>({
  required List<T> shuffled,
  required List<T> incoming,
  required int currentIndex,
  required Object? Function(T) key,
  Random? random,
}) {
  if (incoming.isEmpty) return (queue: <T>[], index: 0);
  if (shuffled.isEmpty) {
    return (queue: List<T>.of(incoming), index: 0);
  }

  // Новые экземпляры тех же треков — по ключу
  final fresh = <Object?, T>{};
  for (final item in incoming) {
    fresh.putIfAbsent(key(item), () => item);
  }

  final index = currentIndex.clamp(0, shuffled.length - 1);
  final currentKey = key(shuffled[index]);

  // Порядок берём у старой очереди, экземпляры — у новой
  final kept = <T>[];
  var keptCurrent = -1;
  for (var i = 0; i < shuffled.length; i++) {
    final item = fresh[key(shuffled[i])];
    if (item == null) continue; // трек удалили из медиатеки
    if (key(shuffled[i]) == currentKey) keptCurrent = kept.length;
    kept.add(item);
  }

  // Чего в очереди ещё не было
  final knownKeys = shuffled.map(key).toSet();
  final added = [
    for (final item in incoming)
      if (!knownKeys.contains(key(item))) item,
  ];

  if (added.isEmpty) {
    return (
      queue: kept,
      index: keptCurrent < 0 ? index.clamp(0, kept.length - 1) : keptCurrent,
    );
  }

  // Играющий трек исчез — вставлять «после текущего» некуда, ставим новое
  // в конец и начинаем с того места, где были
  if (keptCurrent < 0) {
    final queue = [...kept, ...added..shuffle(random)];
    return (queue: queue, index: index.clamp(0, queue.length - 1));
  }

  // Новые — вразброс по ещё не сыгранной части
  final rng = random ?? Random();
  final queue = List<T>.of(kept);
  for (final item in added..shuffle(rng)) {
    final from = keptCurrent + 1;
    final at = from + rng.nextInt(queue.length - from + 1);
    queue.insert(at, item);
  }
  return (queue: queue, index: keptCurrent);
}
