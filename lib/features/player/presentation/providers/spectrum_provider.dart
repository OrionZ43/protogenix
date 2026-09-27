// lib/features/player/presentation/providers/spectrum_provider.dart
//
// Спектр текущего трека — то, по чему двигается визуализатор.
// Считается один раз на трек и лежит на диске (`data/spectrum_store.dart`).
// Пока считается (обычно меньше секунды) — null, и визуализатор дышит ровно.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/spectrum_store.dart';
import '../../domain/spectrogram.dart';
import '../../domain/track_model.dart';
import 'player_provider.dart';

/// Ключ семейства — запись, а не `TrackModel`: модель сравнивается по ссылке
/// и пересоздаётся при каждой перезагрузке очереди (как у огибающей,
/// `envelope_provider.dart`).
typedef SpectrumRequest = ({String id, String? filePath});

final trackSpectrumProvider =
    FutureProvider.autoDispose.family<Spectrogram?, SpectrumRequest>(
  (ref, request) => SpectrumStore.instance.forTrack(
    trackId: request.id,
    filePath: request.filePath,
  ),
);

/// Спектр того трека, что играет сейчас.
final currentSpectrumProvider = Provider.autoDispose<Spectrogram?>((ref) {
  final request = ref.watch(playerProvider.select((s) {
    final track = s.currentTrack as TrackModel?;
    if (track == null) return null;
    return (id: track.id, filePath: track.filePath);
  }));
  if (request == null) return null;
  return ref.watch(trackSpectrumProvider(request)).valueOrNull;
});
