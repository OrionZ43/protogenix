// lib/features/search/presentation/providers/search_provider.dart
//
// Поиск музыки.
//
// Архитектура:
//  Пробуем YouTube через youtube_explode_dart. При сетевой ошибке пробрасываем её.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// ── Чистая модель результата поиска ──────────────────────────────────────────
//
// Не зависит от youtube_explode_dart.Video — позволяет использовать
// разные источники (YouTube) без изменений UI.

class SearchTrack {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String highResThumbnailUrl;
  final Duration duration;

  const SearchTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.highResThumbnailUrl,
    required this.duration,
  });
}

// ── Состояние поиска ──────────────────────────────────────────────────────────

class SearchResult {
  final List<SearchTrack> tracks;

  const SearchResult({
    this.tracks = const [],
  });

  bool get isEmpty => tracks.isEmpty;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SearchNotifier extends AsyncNotifier<SearchResult> {
  Timer? _debounce;

  @override
  Future<SearchResult> build() async {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchResult();
  }

  void search(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const AsyncData(SearchResult());
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 450), () async {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() => _performSearch(query.trim()));
    });
  }

  Future<SearchResult> _performSearch(String query) async {
    // ── 1. Попытка через YouTube ───────────────────────────────────────────
    final yt = YoutubeExplode();
    try {
      final results = await yt.search
          .search(query)
          .timeout(const Duration(seconds: 8));

      final tracks = results
          .map((v) => SearchTrack(
                id: v.id.value,
                title: v.title,
                artist: v.author,
                thumbnailUrl: v.thumbnails.lowResUrl,
                highResThumbnailUrl: v.thumbnails.highResUrl,
                duration: v.duration ?? Duration.zero,
              ))
          .toList();

      debugPrint('[Search] YouTube: ${tracks.length} результатов');
      return SearchResult(tracks: tracks);
    } catch (e) {
      debugPrint('[Search] Ошибка YouTube: $e');
      rethrow;
    } finally {
      yt.close();
    }
  }
}

final searchProvider =
    AsyncNotifierProvider<SearchNotifier, SearchResult>(SearchNotifier.new);
