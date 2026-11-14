import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as p;

class GalleryMediaItem {
  final String id;
  final AssetEntity? asset;
  final File? file;
  final DateTime date;

  GalleryMediaItem({
    required this.id,
    this.asset,
    this.file,
    required this.date,
  });

  Future<File?> getFile() async {
    if (file != null && file!.existsSync()) return file;
    if (asset != null) {
      try {
        final f = await asset!.file;
        if (f != null && f.existsSync()) return f;
      } catch (_) {}
    }
    return null;
  }
}

class GalleryService extends ChangeNotifier {
  static final GalleryService instance = GalleryService._();
  GalleryService._();

  List<GalleryMediaItem> _items = [];
  List<GalleryMediaItem> get items => List.unmodifiable(_items);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  bool _permissionDenied = false;
  bool get permissionDenied => _permissionDenied;

  Future<void> preload() async {
    if (_hasLoaded || _isLoading) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final List<GalleryMediaItem> discovered = [];

      // 1. Mobile (iOS / Android) using PhotoManager
      if (Platform.isIOS || Platform.isAndroid) {
        try {
          final PermissionState ps = await PhotoManager.requestPermissionExtend();
          if (ps.isAuth || ps.hasAccess) {
            _permissionDenied = false;
            final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
              type: RequestType.image,
              onlyAll: true,
            );
            if (albums.isNotEmpty) {
              final List<AssetEntity> assets = await albums.first.getAssetListPaged(
                page: 0,
                size: 80,
              );
              for (final a in assets) {
                discovered.add(
                  GalleryMediaItem(
                    id: a.id,
                    asset: a,
                    date: a.createDateTime,
                  ),
                );
              }
            }
          } else {
            _permissionDenied = true;
          }
        } catch (e) {
          debugPrint('GalleryService mobile error: $e');
        }
      }

      // 2. Windows / Desktop
      if (Platform.isWindows) {
        try {
          final userProfile = Platform.environment['USERPROFILE'];
          final List<String> searchDirs = [];
          if (userProfile != null && userProfile.isNotEmpty) {
            searchDirs.add(p.join(userProfile, 'Pictures', 'Screenshots'));
            searchDirs.add(p.join(userProfile, 'Pictures', 'Camera Roll'));
            searchDirs.add(p.join(userProfile, 'Pictures', 'Saved Pictures'));
            searchDirs.add(p.join(userProfile, 'Pictures'));
            searchDirs.add(p.join(userProfile, 'Downloads'));
            searchDirs.add(p.join(userProfile, 'Desktop'));
            searchDirs.add(p.join(userProfile, 'OneDrive', 'Pictures'));
          }

          final validExts = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};
          final List<File> files = [];

          for (final dirPath in searchDirs) {
            final dir = Directory(dirPath);
            if (await dir.exists()) {
              try {
                await for (final entity in dir.list(followLinks: false)) {
                  if (entity is File) {
                    final ext = p.extension(entity.path).toLowerCase();
                    if (validExts.contains(ext)) {
                      files.add(entity);
                    }
                  }
                }
              } catch (_) {}
            }
          }

          files.sort((a, b) {
            try {
              return b.lastModifiedSync().compareTo(a.lastModifiedSync());
            } catch (_) {
              return 0;
            }
          });

          for (final f in files.take(80)) {
            discovered.add(
              GalleryMediaItem(
                id: f.path,
                file: f,
                date: f.lastModifiedSync(),
              ),
            );
          }
        } catch (e) {
          debugPrint('GalleryService Windows error: $e');
        }
      }

      _items = discovered;
      _hasLoaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addManualFiles(List<File> newFiles) {
    for (final f in newFiles) {
      if (!_items.any((item) => item.file?.path == f.path)) {
        _items.insert(
          0,
          GalleryMediaItem(
            id: f.path,
            file: f,
            date: DateTime.now(),
          ),
        );
      }
    }
    notifyListeners();
  }
}

