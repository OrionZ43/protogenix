package z43.studios.protogenix

import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Музыка на телефоне (lib/features/importer/data/device_music.dart):
        // список из MediaStore. Разрешение на чтение аудио запрашивает Dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "queryAudio") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Запрос может идти секунды на большой медиатеке — не на UI-потоке
                Thread {
                    try {
                        val tracks = queryAudio()
                        runOnUiThread { result.success(tracks) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("query_failed", e.message, null) }
                    }
                }.start()
            }
    }

    private fun queryAudio(): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
        )
        // Только музыка и не короче 30 секунд — без рингтонов, уведомлений
        // и голосовых
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND " +
            "${MediaStore.Audio.Media.DURATION} >= 30000"
        val tracks = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            null,
            "${MediaStore.Audio.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            val path = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val title = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val duration = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (cursor.moveToNext()) {
                val file = cursor.getString(path) ?: continue
                tracks.add(
                    mapOf(
                        "path" to file,
                        "title" to cursor.getString(title),
                        "artist" to cursor.getString(artist),
                        "album" to cursor.getString(album),
                        "durationMs" to cursor.getLong(duration),
                    )
                )
            }
        }
        return tracks
    }

    companion object {
        private const val MEDIA_CHANNEL = "z43.studios.protogenix/media"
    }
}
