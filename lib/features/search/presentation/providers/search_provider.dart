// lib/features/search/presentation/providers/search_provider.dart
//
// Поиск музыки с автоматическим фолбэком на Invidious.
//
// Архитектура:
//  1. Пробуем YouTube через youtube_explode_dart (таймаут 8 сек)
//  2. При любой сетевой ошибке (SocketException, HandshakeException,
//     HttpException, TimeoutException или иной) — переключаемся на
//     поиск через Invidious API /api/v1/search
//  3. SearchResult.usingProxy == true сигнализирует UI включить баннер
//     и показать фразы «слом 4-й стены»

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../../../core/services/invidious_proxy_service.dart';

// ── Чистая модель результата поиска ──────────────────────────────────────────
//
// Не зависит от youtube_explode_dart.Video — позволяет использовать
// разные источники (YouTube, Invidious) без изменений UI.

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
  final bool usingProxy;

  const SearchResult({
    this.tracks = const [],
    this.usingProxy = false,
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
      return SearchResult(tracks: tracks, usingProxy: false);
    } on SocketException catch (e) {
      debugPrint('[Search] SocketException — переходим на Invidious: $e');
    } on HandshakeException catch (e) {
      debugPrint('[Search] HandshakeException — переходим на Invidious: $e');
    } on HttpException catch (e) {
      debugPrint('[Search] HttpException — переходим на Invidious: $e');
    } on TimeoutException catch (e) {
      debugPrint('[Search] Таймаут — переходим на Invidious: $e');
    } catch (e) {
      debugPrint('[Search] Ошибка YouTube — переходим на Invidious: $e');
    } finally {
      yt.close();
    }

    // ── 2. Фолбэк на Invidious ────────────────────────────────────────────
    debugPrint('[Search] Используем Invidious...');
    final invResults =
        await InvidiousProxyService.instance.searchVideos(query);

    final tracks = invResults
        .map((r) => SearchTrack(
              id: r.videoId,
              title: r.title,
              artist: r.author,
              thumbnailUrl: r.thumbnailUrl,
              highResThumbnailUrl: r.highResThumbnailUrl,
              duration: r.duration,
            ))
        .toList();

    debugPrint('[Search] Invidious: ${tracks.length} результатов');
    return SearchResult(tracks: tracks, usingProxy: true);
  }
}

final searchProvider =
    AsyncNotifierProvider<SearchNotifier, SearchResult>(SearchNotifier.new);
