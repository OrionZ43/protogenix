import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/library_database.dart';
import '../domain/library_track.dart';

class LibraryNotifier extends StateNotifier<List<LibraryTrack>> {
  LibraryNotifier() : super([]) {
    reload();
  }

  Future<void> reload() async {
    final tracks = await LibraryDatabase.instance.getAllTracks();
    state = tracks;
  }

  Future<void> removeTrack(String id) async {
    await LibraryDatabase.instance.deleteTrack(id);
    state = state.where((t) => t.id != id).toList();
  }
}

final libraryProvider =
StateNotifierProvider<LibraryNotifier, List<LibraryTrack>>((ref) {
  return LibraryNotifier();
});
