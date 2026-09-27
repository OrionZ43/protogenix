// lib/features/player/presentation/providers/envelope_provider.dart
//
// Огибающая громкости текущего трека: её рисуют волна под прогрессом и
// визуализатор. Считается один раз на трек и лежит на диске
// (`data/envelope_store.dart`); формат не разобрали — null, и волна тогда
// синтетическая, как была.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/envelope_store.dart';
import '../../domain/audio_envelope.dart';
import '../../domain/track_model.dart';
import 'player_provider.dart';

/// Ключ семейства — запись, а не `TrackModel`: модель сравнивается по ссылке
/// и пересоздаётся при каждой перезагрузке очереди, а по значениям один и тот
/// же трек всегда даёт один и тот же провайдер.
typedef EnvelopeRequest = ({String id, String? filePath, int durationMs});

final trackEnvelopeProvider =
    FutureProvider.autoDispose.family<AudioEnvelope?, EnvelopeRequest>(
  (ref, request) => EnvelopeStore.instance.forTrack(
    trackId: request.id,
    filePath: request.filePath,
    durationMs: request.durationMs,
  ),
);

/// Огибающая того трека, что играет сейчас. Пока считается — null, и волна
/// остаётся синтетической; как посчитается, сменится сама.
final currentEnvelopeProvider = Provider.autoDispose<AudioEnvelope?>((ref) {
  final request = ref.watch(playerProvider.select((s) {
    final track = s.currentTrack as TrackModel?;
    if (track == null) return null;
    return (
      id: track.id,
      filePath: track.filePath,
      durationMs: track.duration.inMilliseconds,
    );
  }));
  if (request == null) return null;
  return ref.watch(trackEnvelopeProvider(request)).valueOrNull;
});
