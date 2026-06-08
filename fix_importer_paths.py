import re

with open('lib/features/importer/data/importer_service.dart', 'r') as f:
    content = f.read()

# Replace _getTrackPath
new_get_track_path = """  Future<String> _getTrackPath(String fileName) async {
    final safeFileName = p.basename(fileName).replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_]'), '_');
    final dir = await getApplicationDocumentsDirectory();
    final music = Directory(p.join(dir.path, 'music'));
    await music.create(recursive: true);
    return p.join(music.path, safeFileName);
  }"""

content = re.sub(r'  Future<String> _getTrackPath\(String fileName\) async \{\n    final dir = await getApplicationDocumentsDirectory\(\);\n    final music = Directory\(p\.join\(dir\.path, \'music\'\)\);\n    await music\.create\(recursive: true\);\n    return p\.join\(music\.path, fileName\);\n  \}', new_get_track_path, content)

# Replace _downloadCover
new_download_cover = """  Future<String?> _downloadCover(String url, String trackId) async {
    try {
      final safeTrackId = p.basename(trackId).replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_]'), '_');
      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
      await coversDir.create(recursive: true);
      final path = p.join(coversDir.path, '$safeTrackId.jpg');
      await _dio.download(url, path);
      return path;
    } catch (e) {
      debugPrint('Ошибка загрузки обложки: $e');
      return null;
    }
  }"""

content = re.sub(r'  Future<String\?> _downloadCover\(String url, String trackId\) async \{\n    try \{\n      final dir = await getApplicationDocumentsDirectory\(\);\n      final coversDir = Directory\(p\.join\(dir\.path, \'covers\'\)\);\n      await coversDir\.create\(recursive: true\);\n      final path = p\.join\(coversDir\.path, \'\$trackId\.jpg\'\);\n      await _dio\.download\(url, path\);\n      return path;\n    \} catch \(_\) \{\n      return null;\n    \}\n  \}', new_download_cover, content)

with open('lib/features/importer/data/importer_service.dart', 'w') as f:
    f.write(content)
