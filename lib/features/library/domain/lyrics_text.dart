// lib/features/library/domain/lyrics_text.dart
//
// Сравнение названий и артистов при поиске текстов.
//
// Буквы любого алфавита сохраняются. Прежняя нормализация вычищала всё, что не
// `\w`, а `\w` в регулярках Dart — только латиница и цифры: у русских песен от
// названия оставалась пустая строка, и все варианты получали одинаковую оценку
// (замер 2026-09-12). «ё» приравнивается к «е», кириллица дополнительно
// сравнивается в транслите («Kino» ≈ «Кино»).

import 'package:string_similarity/string_similarity.dart';

final _nonLetterOrDigit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Нижний регистр, «ё» → «е», только буквы и цифры через одиночный пробел.
String normalizeForMatch(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(_nonLetterOrDigit, ' ')
    .trim();

const _translit = <String, String>{
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh',
  'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
  'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
  'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y',
  'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya', 'і': 'i', 'ї': 'i', 'є': 'e',
  'ў': 'u', 'ґ': 'g',
};

/// Кириллица → латиница для уже нормализованной строки.
String transliterate(String normalized) {
  final out = StringBuffer();
  for (final rune in normalized.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_translit[ch] ?? ch);
  }
  return out.toString();
}

/// Сходство строк 0…1: лучшее из сравнения как есть, в транслите и без
/// пробелов («TheWeeknd» ≈ «The Weeknd»).
double textSimilarity(String a, String b) {
  final na = normalizeForMatch(a);
  final nb = normalizeForMatch(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  final ta = transliterate(na);
  final tb = transliterate(nb);
  final sa = ta.replaceAll(' ', '');
  final sb = tb.replaceAll(' ', '');
  if (na == nb || ta == tb || sa == sb) return 1;

  var best = na.similarityTo(nb);
  final translit = ta.similarityTo(tb);
  if (translit > best) best = translit;
  final squashed = sa.similarityTo(sb);
  if (squashed > best) best = squashed;
  return best;
}

final _artistSeparators = RegExp(
  r'\s*(?:,|&|/|;|\+|、)\s*'
  r'|\s+(?:x|х|и|and|with|vs\.?|feat\.?|ft\.?|featuring)\s+',
  caseSensitive: false,
);

/// «5opka, MellSher», «5opka & MellSher», «5opka и илюха реп» → по одному.
List<String> splitArtists(String s) => s
    .split(_artistSeparators)
    .map((a) => a.trim())
    .where((a) => a.isNotEmpty)
    .toList();

/// Лучшее сходство среди пар артистов.
double artistSimilarity(List<String> a, List<String> b) {
  var best = 0.0;
  for (final x in a) {
    for (final y in b) {
      final s = textSimilarity(x, y);
      if (s > best) best = s;
    }
  }
  return best;
}
