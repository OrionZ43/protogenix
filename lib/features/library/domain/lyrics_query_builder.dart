// lib/features/library/domain/lyrics_query_builder.dart
//
// Строки свободного поиска по прочтениям названия (track_query.dart):
// «артисты название» основного прочтения, только название, дальше остальные
// прочтения и части попурри. Точные запросы по полям строит
// lyrics_service.dart.

import 'lyrics_text.dart';
import 'track_query.dart';

class LyricsQueryBuilder {
  static final _spaces = RegExp(r'\s+');

  List<String> queries(List<ParsedTrack> interpretations) {
    final result = <String>[];
    final seen = <String>{};
    void add(String query) {
      final clean = query.replaceAll(_spaces, ' ').trim();
      final key = normalizeForMatch(clean);
      if (key.isNotEmpty && seen.add(key)) result.add(clean);
    }

    final primary = interpretations.first;
    add('${primary.artists.join(' ')} ${primary.title}');
    add(primary.title);
    for (final t in interpretations.skip(1)) {
      add('${t.artists.join(' ')} ${t.title}');
    }
    for (final part in primary.titles.skip(1)) {
      add('${primary.artists.join(' ')} $part');
    }
    return result;
  }
}
