import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/youtube_match.dart';

YoutubeCandidate _c(String id, int seconds, String author, String title) =>
    YoutubeCandidate(
        id: id, title: title, author: author, durationMs: seconds * 1000);

/// Поиск-заглушка: выдача по запросу и журнал запросов. Запроса нет в
/// выдачах — ошибка, как у упавшего поиска.
class _FakeSearch {
  _FakeSearch(this.results);

  final Map<String, List<YoutubeCandidate>> results;
  final queries = <String>[];

  Future<List<YoutubeCandidate>> call(String query) async {
    queries.add(query);
    final found = results[query];
    if (found == null) throw StateError('нет выдачи для «$query»');
    return found;
  }
}

void main() {
  // Выдачи — по живой проверке 2026-09-14: «Queen — Don't Stop Me Now -
  // Remastered 2011» со Spotify, 209 с
  const title = "Don't Stop Me Now (Remastered 2011)";
  const first = "Queen - Don't Stop Me Now (Remastered 2011)";
  const second = "Queen Don't Stop Me Now (Remastered 2011) topic";
  final fan = _c('fan', 210, 'Alessandro Rossi',
      "Queen - Don't Stop Me Now (Remastered 2011)");
  final live = _c('live', 212, 'Queen Official',
      "Don't Stop Me Now (Live at Montreal 1981)");
  final topic =
      _c('topic', 209, 'Queen - Topic', "Don't Stop Me Now - Remastered 2011");

  Future<YoutubeCandidate?> find(_FakeSearch search,
          {String artist = 'Queen', String query = title}) =>
      findYoutubeUpload(
        matcher: YoutubeTrackMatcher(
            title: query, artist: artist, durationMs: 209000),
        title: query,
        artist: artist,
        search: search.call,
      );

  test('первый ролик не с официального канала — ещё запрос с topic', () async {
    final search = _FakeSearch({
      first: [live, fan],
      second: [topic, fan],
    });
    expect((await find(search))?.id, 'topic');
    expect(search.queries, [first, second]);
  });

  test('первый же ролик официальный — второго запроса нет', () async {
    final search = _FakeSearch({
      first: [fan, topic],
    });
    expect((await find(search))?.id, 'topic');
    expect(search.queries, [first]);
  });

  test('в первой выдаче ничего подходящего — находится во второй', () async {
    final search = _FakeSearch({
      first: [live],
      second: [topic],
    });
    expect((await find(search))?.id, 'topic');
  });

  test('добавочный запрос упал — остаётся уже найденное', () async {
    final search = _FakeSearch({
      first: [fan],
    });
    expect((await find(search))?.id, 'fan');
    expect(search.queries, [first, second]);
  });

  test('первый запрос упал — ошибка уходит наверх', () async {
    expect(find(_FakeSearch({})), throwsStateError);
  });

  test('без исполнителя — один запрос по названию', () async {
    const plain = "Don't Stop Me Now";
    final search = _FakeSearch({
      plain: [topic],
    });
    expect((await find(search, artist: '', query: plain))?.id, 'topic');
    expect(search.queries, [plain]);
  });

  test('канал «Queen Official» — официальный, перезалив фаната — нет', () {
    final matcher =
        YoutubeTrackMatcher(title: title, artist: 'Queen', durationMs: 209000);
    expect(
        matcher.isOfficial(_c('video', 212, 'Queen Official',
            "Queen - Don't Stop Me Now (Official Video)")),
        isTrue);
    expect(matcher.isOfficial(fan), isFalse);
    expect(matcher.isOfficial(_c('x', 209, 'Official', title)), isFalse);
  });
}
