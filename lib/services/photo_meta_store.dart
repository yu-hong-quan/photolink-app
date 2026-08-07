import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用侧照片扩展元数据：显示名 / 归类相册名（系统文件名不可靠改写时兜底）
class PhotoMetaStore {
  PhotoMetaStore._();
  static final PhotoMetaStore instance = PhotoMetaStore._();

  Map<String, Map<String, dynamic>> _cache = {};
  File? _file;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'photolink_photo_meta.json'));
    if (await _file!.exists()) {
      try {
        final map = jsonDecode(await _file!.readAsString());
        if (map is Map) {
          _cache = map.map(
            (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
          );
        }
      } catch (_) {
        _cache = {};
      }
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    await _ensureLoaded();
    await _file!.writeAsString(jsonEncode(_cache));
  }

  Future<String?> getDisplayTitle(String photoId) async {
    await _ensureLoaded();
    return _cache[photoId]?['title']?.toString();
  }

  Future<String?> getAlbumName(String photoId) async {
    await _ensureLoaded();
    return _cache[photoId]?['albumName']?.toString();
  }

  Future<void> setDisplayTitle(String photoId, String title) async {
    await _ensureLoaded();
    final entry = Map<String, dynamic>.from(_cache[photoId] ?? {});
    entry['title'] = title;
    _cache[photoId] = entry;
    await _persist();
  }

  Future<void> setAlbumName(String photoId, String albumName) async {
    await _ensureLoaded();
    final entry = Map<String, dynamic>.from(_cache[photoId] ?? {});
    entry['albumName'] = albumName;
    _cache[photoId] = entry;
    await _persist();
  }

  Future<void> remove(String photoId) async {
    await _ensureLoaded();
    _cache.remove(photoId);
    await _persist();
  }

  Future<Map<String, dynamic>?> get(String photoId) async {
    await _ensureLoaded();
    return _cache[photoId];
  }
}
