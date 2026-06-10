import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class SearchNotifier extends AsyncNotifier<List<Video>> {
  Timer? _debounce;

  @override
  Future<List<Video>> build() async {
    ref.onDispose(() => _debounce?.cancel());
    return [];
  }

  void search(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 450), () async {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() async {
        final yt = YoutubeExplode();
        try {
          final results = await yt.search.search(query.trim());
          return results.toList();
        } finally {
          yt.close();
        }
      });
    });
  }
}

final searchProvider = AsyncNotifierProvider<SearchNotifier, List<Video>>(SearchNotifier.new);
