import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../data/database_helper.dart';

class StorageUsage {
  final int photosBytes;
  final int voicesBytes;
  final int databaseBytes;
  final int otherBytes;

  const StorageUsage({
    this.photosBytes = 0,
    this.voicesBytes = 0,
    this.databaseBytes = 0,
    this.otherBytes = 0,
  });

  int get totalCacheBytes => photosBytes + voicesBytes + otherBytes;
  int get totalAllBytes => photosBytes + voicesBytes + databaseBytes + otherBytes;
}

class MediaCacheService {
  static final MediaCacheService instance = MediaCacheService._();
  MediaCacheService._();

  final BaseCacheManager cacheManager = DefaultCacheManager();
  final Dio _dio = Dio();

  /// Gets the directory where persistent voice messages are cached
  Future<Directory> getVoicesCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'portal_cache', 'voices'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Gets the directory where persistent photos are cached
  Future<Directory> getPhotosCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'portal_cache', 'photos'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Precaches a photo URL into disk cache in the background
  Future<File?> precachePhoto(String rawUrl) async {
    if (rawUrl.isEmpty) return null;
    if (File(rawUrl).existsSync()) return File(rawUrl);

    final fullUrl = AppConstants.formatMediaUrl(rawUrl);
    if (!fullUrl.startsWith('http')) return null;

    try {
      final fileInfo = await cacheManager.getFileFromCache(fullUrl);
      if (fileInfo != null && fileInfo.file.existsSync()) {
        return fileInfo.file;
      }
      final file = await cacheManager.getSingleFile(fullUrl);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Precaches all photos inside a [PORTAL_PHOTO] payload
  Future<void> precacheMessagePhotos(String text) async {
    if (!text.contains('[PORTAL_PHOTO]:')) return;
    try {
      final startIdx = text.indexOf('{');
      final endIdx = text.lastIndexOf('}');
      if (startIdx == -1 || endIdx <= startIdx) return;
      final jsonStr = text.substring(startIdx, endIdx + 1);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      List<String> urls = [];
      if (map['urls'] is List) {
        urls = (map['urls'] as List).map((e) => e.toString()).toList();
      } else if (map['url'] != null) {
        urls = [map['url'].toString()];
      }
      for (final u in urls) {
        if (u.isNotEmpty) {
          precachePhoto(u);
        }
      }
    } catch (_) {}
  }

  /// Downloads or retrieves a cached voice message file
  Future<String> getOrCacheVoice(String rawUrl) async {
    if (rawUrl.isEmpty) return '';
    if (File(rawUrl).existsSync()) return rawUrl;

    final fullUrl = AppConstants.formatMediaUrl(rawUrl);
    if (!fullUrl.startsWith('http')) return rawUrl;

    try {
      final dir = await getVoicesCacheDir();
      final hash = md5.convert(utf8.encode(fullUrl)).toString();
      final ext = p.extension(fullUrl).isNotEmpty ? p.extension(fullUrl) : '.m4a';
      final cachedFile = File(p.join(dir.path, 'voice_$hash$ext'));

      if (cachedFile.existsSync() && cachedFile.lengthSync() > 0) {
        return cachedFile.path;
      }

      await _dio.download(fullUrl, cachedFile.path);
      return cachedFile.path;
    } catch (_) {
      return fullUrl;
    }
  }

  /// Calculates disk space used by cache, media, and database
  Future<StorageUsage> calculateStorageUsage() async {
    int photosSize = 0;
    int voicesSize = 0;
    int dbSize = 0;
    int otherTempSize = 0;

    // 1. Photos in DefaultCacheManager (in temp dir)
    try {
      final tempDir = await getTemporaryDirectory();
      final libCacheDir = Directory(p.join(tempDir.path, 'libCachedImageData'));
      if (libCacheDir.existsSync()) {
        photosSize += _getDirectorySize(libCacheDir);
      }
      // Also custom photos dir
      final photosDir = await getPhotosCacheDir();
      photosSize += _getDirectorySize(photosDir);
    } catch (_) {}

    // 2. Voices cache
    try {
      final voicesDir = await getVoicesCacheDir();
      voicesSize += _getDirectorySize(voicesDir);
    } catch (_) {}

    // 3. Database
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(docsDir.path, 'portal.db'));
      if (dbFile.existsSync()) {
        dbSize += dbFile.lengthSync();
      }
      final dbWal = File(p.join(docsDir.path, 'portal.db-wal'));
      if (dbWal.existsSync()) {
        dbSize += dbWal.lengthSync();
      }
    } catch (_) {}

    // 4. Other temporary cache
    try {
      final tempDir = await getTemporaryDirectory();
      final totalTemp = _getDirectorySize(tempDir);
      final libCacheDir = Directory(p.join(tempDir.path, 'libCachedImageData'));
      final libCacheSize = libCacheDir.existsSync() ? _getDirectorySize(libCacheDir) : 0;
      otherTempSize = (totalTemp - libCacheSize).clamp(0, 1000000000);
    } catch (_) {}

    return StorageUsage(
      photosBytes: photosSize,
      voicesBytes: voicesSize,
      databaseBytes: dbSize,
      otherBytes: otherTempSize,
    );
  }

  int _getDirectorySize(Directory dir) {
    if (!dir.existsSync()) return 0;
    int total = 0;
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
    } catch (_) {}
    return total;
  }

  /// Clears photo and image cache
  Future<void> clearPhotosCache() async {
    try {
      await cacheManager.emptyCache();
    } catch (_) {}
    try {
      final photosDir = await getPhotosCacheDir();
      if (photosDir.existsSync()) {
        photosDir.deleteSync(recursive: true);
        photosDir.createSync(recursive: true);
      }
    } catch (_) {}
    // Clear Flutter memory cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// Clears voice message cache
  Future<void> clearVoicesCache() async {
    try {
      final voicesDir = await getVoicesCacheDir();
      if (voicesDir.existsSync()) {
        voicesDir.deleteSync(recursive: true);
        voicesDir.createSync(recursive: true);
      }
    } catch (_) {}
  }

  /// Clears all media and temporary cache
  Future<void> clearAllCache() async {
    await clearPhotosCache();
    await clearVoicesCache();
    try {
      final tempDir = await getTemporaryDirectory();
      for (final entity in tempDir.listSync(followLinks: false)) {
        try {
          if (entity is File) {
            entity.deleteSync();
          } else if (entity is Directory) {
            entity.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Optimizes SQLite database
  Future<void> optimizeDatabase() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.rawQuery('VACUUM');
    } catch (_) {}
  }

  /// Formats byte count into human-readable string (e.g. 14.5 МБ)
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 Б';
    const suffixes = ['Б', 'КБ', 'МБ', 'ГБ'];
    int i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    if (i == 0) return '${d.toInt()} ${suffixes[i]}';
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }
}

