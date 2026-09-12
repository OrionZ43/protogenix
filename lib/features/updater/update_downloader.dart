// lib/features/updater/update_downloader.dart
//
// Скачивание файла обновления:
//   • адреса из манифеста перебираются по очереди, при сбое берётся следующий;
//   • оборванная загрузка продолжается с места обрыва (HTTP Range), если
//     сервер это поддерживает, иначе файл качается заново;
//   • готовый файл сверяется по размеру и SHA-256 из подписанного манифеста;
//     хэш считается в отдельном изоляте, чтобы не тормозить интерфейс;
//   • уже скачанный и проверенный файл повторно не качается.

import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'update_manifest.dart';

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'UpdateDownloadException: $message${cause == null ? '' : ' ($cause)'}';
}

class UpdateDownloader {
  UpdateDownloader({required this.directory, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  /// Куда складывать файлы обновления.
  final Directory directory;
  final Dio _dio;

  /// Скачивает и проверяет файл. [onProgress] получает долю от 0 до 1.
  Future<File> download(
    UpdateAsset asset, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, asset.fileName));
    if (await _isComplete(target, asset)) {
      onProgress?.call(1);
      return target;
    }

    final part = File('${target.path}.part');
    Object? lastError;
    for (final url in asset.urls) {
      try {
        await _fetch(url, part, asset.size, onProgress, cancelToken);

        final length = await part.length();
        if (length != asset.size) {
          // Недокачанный кусок оставляем: следующий адрес продолжит с него.
          throw UpdateDownloadException(
              'Загрузка оборвалась: $length из ${asset.size} байт');
        }
        if (await sha256OfFile(part.path) != asset.sha256) {
          await part.delete();
          throw const UpdateDownloadException('SHA-256 не совпал с манифестом');
        }

        if (await target.exists()) await target.delete();
        return await part.rename(target.path);
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      debugPrint('[Updater] Не удалось скачать $url: $lastError');
    }
    throw UpdateDownloadException('Не удалось скачать обновление', lastError);
  }

  Future<void> _fetch(
    Uri url,
    File part,
    int total,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  ) async {
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > total) {
      await part.delete();
      offset = 0;
    }
    if (offset == total) return;

    final response = await _dio.getUri<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: {if (offset > 0) HttpHeaders.rangeHeader: 'bytes=$offset-'},
        validateStatus: (status) =>
            status == HttpStatus.ok || status == HttpStatus.partialContent,
      ),
    );

    // 206 — сервер продолжил с нужного места; 200 — прислал файл целиком.
    final resumed = response.statusCode == HttpStatus.partialContent;
    var received = resumed ? offset : 0;
    final sink =
        part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in response.data!.stream) {
        received += chunk.length;
        if (received > total) {
          throw const UpdateDownloadException(
              'Сервер прислал больше, чем указано в манифесте');
        }
        sink.add(chunk);
        onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
  }

  Future<bool> _isComplete(File file, UpdateAsset asset) async {
    if (!await file.exists() || await file.length() != asset.size) {
      return false;
    }
    return await sha256OfFile(file.path) == asset.sha256;
  }
}

/// SHA-256 файла в отдельном изоляте.
Future<String> sha256OfFile(String path) => Isolate.run(() async {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString();
    });
