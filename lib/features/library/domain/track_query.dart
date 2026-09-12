// lib/features/library/domain/track_query.dart
//
// Разбор «грязных» названий: YouTube-заголовков вида
// «5opka, MellSher - XXL (SUPER PUPER NOVA, альбом 2025)» с канала «ФУГА TV»
// и записей LRCLIB, загруженных с такими же заголовками. Трек и найденные
// варианты разбираются одинаково — иначе чистое «Believer» проигрывает
// записи «Imagine Dragons - Believer (Lyrics)».

import 'lyrics_text.dart';

/// Версия трека, у которой другие тайминги или другой текст.
enum TrackVariant {
  remix,
  live,
  acoustic,
  instrumental,
  cover,
  karaoke,
  slowed,
  spedUp,
  nightcore,
  eightD,
  extended,
}

extension TrackVariantX on TrackVariant {
  /// Меняет только скорость: текст оригинала подходит, если растянуть тайминги.
  bool get isSpeedChange =>
      this == TrackVariant.slowed ||
      this == TrackVariant.spedUp ||
      this == TrackVariant.nightcore;
}

class ParsedTrack {
  const ParsedTrack({
    required this.titles,
    required this.artists,
    required this.variants,
  });

  /// Первое — основное название; дальше части попурри «Intro/Starboy».
  final List<String> titles;

  /// Артисты по одному; пусто — артист неизвестен.
  final List<String> artists;

  final Set<TrackVariant> variants;

  String get title => titles.first;

  @override
  String toString() => '${artists.join(' & ')} — ${titles.join(' / ')}'
      '${variants.isEmpty ? '' : ' [${variants.map((v) => v.name).join(', ')}]'}';
}

class TrackQueryParser {
  TrackQueryParser._();

  static final _brackets = RegExp(r'[(\[{【（]([^)\]}】）]*)[)\]}】）]');
  static final _pipe = RegExp(r'\s+(?:\||//)\s+');
  static final _dash = RegExp(r'\s+[-–—]\s+');
  static final _feat = RegExp(
    r'\s+(?:feat\.?|ft\.?|featuring|при\s+участии|при\s+уч\.)\s+',
    caseSensitive: false,
  );
  static final _featInBrackets = RegExp(
    r'^\s*(?:feat\.?|ft\.?|featuring|при\s+участии|при\s+уч\.)\s+(.+)$',
    caseSensitive: false,
  );
  static final _trackNumber = RegExp(r'^\s*\d{1,3}\s*[.)]\s+');
  static final _trailingJunk = RegExp(
    r'(?:\s*[-–—|]\s*|\s+)(?:official\s+(?:music\s+)?(?:video|audio|lyric\s+video|visualizer)'
    r'|lyric\s+video|lyrics?|клип|премьера(?:\s+клипа)?|official)\s*$',
    caseSensitive: false,
  );
  static final _uploaderSuffix = RegExp(
    r'\s*(?:-\s*topic|vevo|-\s*official(?:\s+channel)?|official\s+channel)\s*$',
    caseSensitive: false,
  );
  static final _unknownArtist = RegExp(
    r'^(?:unknown(?:\s+artist)?|various\s+artists|неизвестный(?:\s+исполнитель)?)$',
    caseSensitive: false,
  );
  static final _reverb =
      RegExp(r'\s*(?:\+|&|and|и)?\s*reverb\b', caseSensitive: false);
  static final _edgePunctuation =
      RegExp(r'^[\s\-–—|:,."«»“”]+|[\s\-–—|:,."«»“”]+$');
  static final _spaces = RegExp(r'\s+');
  static final _year = RegExp(r'^\d{4}$');

  static final _variantPatterns = <TrackVariant, RegExp>{
    TrackVariant.remix:
        RegExp(r'remix|\brmx\b|ремикс|bootleg', caseSensitive: false),
    TrackVariant.live: RegExp(r'\blive\b|концерт|живое|вживую|unplugged',
        caseSensitive: false),
    TrackVariant.acoustic: RegExp(r'acoustic|акустик', caseSensitive: false),
    TrackVariant.instrumental: RegExp(
        r'instrumental|инструментал|минус|backing\s+track',
        caseSensitive: false),
    TrackVariant.karaoke: RegExp(r'karaoke|караоке', caseSensitive: false),
    TrackVariant.cover: RegExp(r'\bcover\b|кавер', caseSensitive: false),
    TrackVariant.slowed: RegExp(r'slowed|замедл\S*', caseSensitive: false),
    TrackVariant.spedUp:
        RegExp(r'sped\s*up|speed\s*up|ускорен\S*', caseSensitive: false),
    TrackVariant.nightcore: RegExp(r'nightcore', caseSensitive: false),
    TrackVariant.eightD: RegExp(r'\b8d\b', caseSensitive: false),
    TrackVariant.extended: RegExp(r'extended|удлин\S*', caseSensitive: false),
  };

  /// Эти версии пишут и без скобок: «ELA DANCA SLOWED», «Мотылёк 8D».
  static const _inlineVariants = [
    TrackVariant.slowed,
    TrackVariant.spedUp,
    TrackVariant.nightcore,
    TrackVariant.eightD,
  ];

  /// Приписки после тире, которые не название: «Song - Remastered 2011»,
  /// «ELA DANCA - Slowed». Слова — в нормализованном виде.
  static const _descriptorWords = {
    'remaster', 'remastered', 'version', 'edit', 'radio', 'mono', 'stereo',
    'mix', 'original', 'single', 'bonus', 'track', 'demo', 'live', 'acoustic',
    'remix', 'rmx', 'slowed', 'reverb', 'sped', 'speed', 'up', 'nightcore',
    '8d', 'extended', 'instrumental', 'karaoke', 'cover', 'ремикс', 'версия',
    'кавер', 'концерт', 'живое', 'акустика', 'акустическая', 'замедленная',
    'замедленно', 'ускоренная', 'минус', 'инструментал',
  };

  /// Основное прочтение.
  static ParsedTrack parse(String rawTitle, String rawArtist) =>
      interpretations(rawTitle, rawArtist).first;

  /// Прочтения по убыванию правдоподобия: «Артист - Название», наоборот
  /// «Название - Артисты» и заголовок целиком с артистом из поля artist.
  static List<ParsedTrack> interpretations(String rawTitle, String rawArtist) {
    final variants = <TrackVariant>{};
    final featured = <String>[];

    // Скобки: версия и feat. из них, сами скобки из названия убираем.
    var title = rawTitle.replaceAllMapped(_brackets, (m) {
      final inner = m.group(1) ?? '';
      _collectVariants(inner, variants);
      final feat = _featInBrackets.firstMatch(inner);
      if (feat != null) featured.addAll(splitArtists(feat.group(1)!));
      return ' ';
    });

    // «Название | Official Video», «Название // приписка».
    final pipeParts = title.split(_pipe);
    if (pipeParts.length > 1 && pipeParts.first.trim().isNotEmpty) {
      for (final extra in pipeParts.skip(1)) {
        _collectVariants(extra, variants);
      }
      title = pipeParts.first;
    }

    for (final v in _inlineVariants) {
      final rx = _variantPatterns[v]!;
      if (rx.hasMatch(title)) {
        variants.add(v);
        title = title.replaceAll(rx, ' ');
      }
    }
    title = title.replaceAll(_reverb, ' ');

    // feat. без скобок: «Starboy ft. Daft Punk».
    final featParts = title.split(_feat);
    if (featParts.length > 1) {
      title = featParts.first;
      for (final f in featParts.skip(1)) {
        featured.addAll(splitArtists(f));
      }
    }

    title = _stripTrailingJunk(title).replaceFirst(_trackNumber, '');

    final uploader = _cleanUploader(rawArtist);
    final uploaderArtists =
        uploader.isEmpty ? <String>[] : splitArtists(uploader);

    // «Артист - Название», «Название - Remastered 2011», «Название - Артисты».
    final dashParts = title.split(_dash).map(_clean).toList();
    while (dashParts.length > 1 && _isDescriptor(dashParts.last)) {
      _collectVariants(dashParts.removeLast(), variants);
    }
    dashParts.removeWhere((p) => p.isEmpty);
    if (dashParts.length >= 2) {
      final left = dashParts.first;
      final right = dashParts.sublist(1).join(' - ');
      return [
        _make(right, splitArtists(left), featured, variants),
        _make(left, splitArtists(right), featured, variants),
        _make('$left $right', uploaderArtists, featured, variants),
      ];
    }
    final single = dashParts.isEmpty ? _clean(title) : dashParts.first;
    return [_make(single, uploaderArtists, featured, variants)];
  }

  static ParsedTrack _make(
    String title,
    List<String> artists,
    List<String> featured,
    Set<TrackVariant> variants,
  ) {
    final main = _clean(title);
    final parts = main.contains('/')
        ? main.split('/').map(_clean).where((p) => p.isNotEmpty && p != main)
        : const <String>[];
    final unique = <String>[];
    for (final a in [...artists, ...featured]) {
      final key = normalizeForMatch(a);
      if (key.isNotEmpty &&
          !unique.any((u) => normalizeForMatch(u) == key)) {
        unique.add(a);
      }
    }
    return ParsedTrack(
      titles: [main, ...parts],
      artists: unique,
      variants: Set.unmodifiable(variants),
    );
  }

  static void _collectVariants(String text, Set<TrackVariant> into) {
    _variantPatterns.forEach((variant, rx) {
      if (rx.hasMatch(text)) into.add(variant);
    });
  }

  static bool _isDescriptor(String s) {
    final words =
        normalizeForMatch(s).split(' ').where((w) => w.isNotEmpty).toList();
    var hasKeyword = false;
    for (final w in words) {
      if (_year.hasMatch(w)) continue;
      if (!_descriptorWords.contains(w)) return false;
      hasKeyword = true;
    }
    return hasKeyword;
  }

  static String _stripTrailingJunk(String s) {
    var result = s;
    for (var i = 0; i < 3; i++) {
      final next = result.replaceFirst(_trailingJunk, '');
      if (next == result) break;
      result = next;
    }
    return result;
  }

  static String _cleanUploader(String raw) {
    final a = _clean(
        raw.replaceAll(_brackets, ' ').replaceAll(_uploaderSuffix, ''));
    return _unknownArtist.hasMatch(a) ? '' : a;
  }

  static String _clean(String s) =>
      s.replaceAll(_spaces, ' ').replaceAll(_edgePunctuation, '').trim();
}
