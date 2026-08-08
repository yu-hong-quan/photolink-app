import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

/// 回收站条目（软删除后的本地备份）
class TrashItem {
  TrashItem({
    required this.id,
    required this.originalPhotoId,
    required this.title,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.createTimeMs,
    required this.deletedAtMs,
    required this.fileName,
    this.mediaType = 'image',
  });

  final String id;
  final String originalPhotoId;
  final String title;
  final String? mimeType;
  final int width;
  final int height;
  final int createTimeMs;
  final int deletedAtMs;
  final String fileName;

  /// image / video，恢复时决定写入系统相册的方式
  final String mediaType;

  bool get isVideo => mediaType == 'video';

  Map<String, dynamic> toJson() => {
        'id': id,
        'trashId': id, // PC 端兼容别名
        'originalPhotoId': originalPhotoId,
        'photoId': originalPhotoId, // PC 端兼容别名
        'title': title,
        'mimeType': mimeType,
        'width': width,
        'height': height,
        'createTimeMs': createTimeMs,
        'deletedAtMs': deletedAtMs,
        'fileName': fileName,
        'mediaType': mediaType,
      };

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    final mime = json['mimeType']?.toString();
    final rawType = json['mediaType']?.toString();
    final fileName = json['fileName']?.toString() ?? 'file.bin';
    // 旧回收站条目无 mediaType 时，按 mime / 扩展名推断
    final mediaType = (rawType != null && rawType.isNotEmpty)
        ? rawType
        : ((mime != null && mime.startsWith('video/')) ||
                _looksLikeVideoExt(fileName)
            ? 'video'
            : 'image');
    return TrashItem(
      id: json['id']?.toString() ?? '',
      originalPhotoId: json['originalPhotoId']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名',
      mimeType: mime,
      width: int.tryParse('${json['width']}') ?? 0,
      height: int.tryParse('${json['height']}') ?? 0,
      createTimeMs: int.tryParse('${json['createTimeMs']}') ?? 0,
      deletedAtMs: int.tryParse('${json['deletedAtMs']}') ?? 0,
      fileName: fileName,
      mediaType: mediaType,
    );
  }
}

bool _looksLikeVideoExt(String name) {
  final lower = name.toLowerCase();
  const exts = ['.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm', '.3gp', '.wmv'];
  return exts.any(lower.endsWith);
}

/// 软删除回收站：先备份原图到 App 目录，再从系统相册删除；可恢复或彻底删除
class TrashService {
  TrashService._();
  static final TrashService instance = TrashService._();

  Directory? _root;

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    _root = Directory(p.join(base.path, 'photolink_trash'));
    if (!await _root!.exists()) {
      await _root!.create(recursive: true);
    }
    return _root!;
  }

  Future<Directory> _itemDir(String trashId) async {
    final root = await _ensureRoot();
    return Directory(p.join(root.path, trashId));
  }

  /// 软删除：先全部备份，再一次性批量删系统相册（避免逐张弹系统「允许删除」）
  Future<List<String>> softDelete(List<String> photoIds) async {
    if (photoIds.isEmpty) return const [];

    final readyIds = <String>[];
    for (final photoId in photoIds) {
      final asset = await AssetEntity.fromId(photoId);
      if (asset == null) continue;
      final origin = await asset.originFile;
      if (origin == null || !await origin.exists()) continue;

      final trashId = const Uuid().v4();
      final dir = await _itemDir(trashId);
      await dir.create(recursive: true);
      final ext = p.extension(origin.path).isNotEmpty
          ? p.extension(origin.path)
          : '.jpg';
      final fileName = 'original$ext';
      final dest = File(p.join(dir.path, fileName));
      await origin.copy(dest.path);

      final item = TrashItem(
        id: trashId,
        originalPhotoId: photoId,
        title: asset.title ?? 'media_$photoId',
        mimeType: asset.mimeType,
        width: asset.width,
        height: asset.height,
        createTimeMs: asset.createDateTime.millisecondsSinceEpoch,
        deletedAtMs: DateTime.now().millisecondsSinceEpoch,
        fileName: fileName,
        mediaType: asset.type == AssetType.video ? 'video' : 'image',
      );
      await File(p.join(dir.path, 'meta.json'))
          .writeAsString(jsonEncode(item.toJson()));

      // 缩略图备份（预览用）
      try {
        final thumb = await asset.thumbnailDataWithSize(
          const ThumbnailSize(256, 256),
          quality: 80,
        );
        if (thumb != null) {
          await File(p.join(dir.path, 'thumb.jpg')).writeAsBytes(thumb);
        }
      } catch (_) {}

      readyIds.add(photoId);
    }

    if (readyIds.isEmpty) return const [];

    // 关键一次系统删除请求，用户点一次「允许」即可批量删除
    final deleted = await PhotoManager.editor.deleteWithIds(readyIds);
    return deleted;
  }

  Future<List<TrashItem>> list() async {
    final root = await _ensureRoot();
    final items = <TrashItem>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final metaFile = File(p.join(entity.path, 'meta.json'));
      if (!await metaFile.exists()) continue;
      try {
        final map =
            jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        items.add(TrashItem.fromJson(map));
      } catch (_) {}
    }
    items.sort((a, b) => b.deletedAtMs.compareTo(a.deletedAtMs));
    return items;
  }

  Future<File?> originalFile(String trashId) async {
    final item = await _readMeta(trashId);
    if (item == null) return null;
    final dir = await _itemDir(trashId);
    final file = File(p.join(dir.path, item.fileName));
    if (await file.exists()) return file;
    return null;
  }

  Future<File?> thumbFile(String trashId) async {
    final dir = await _itemDir(trashId);
    final file = File(p.join(dir.path, 'thumb.jpg'));
    if (await file.exists()) return file;
    return null;
  }

  Future<TrashItem?> _readMeta(String trashId) async {
    final dir = await _itemDir(trashId);
    final metaFile = File(p.join(dir.path, 'meta.json'));
    if (!await metaFile.exists()) return null;
    try {
      return TrashItem.fromJson(
        jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// 撤回：写回系统相册并清理回收站条目（视频走 saveVideo）
  Future<AssetEntity?> restore(String trashId) async {
    final item = await _readMeta(trashId);
    final file = await originalFile(trashId);
    if (item == null || file == null) return null;
    final AssetEntity? entity;
    if (item.isVideo || _looksLikeVideoExt(item.fileName)) {
      entity = await PhotoManager.editor.saveVideo(
        file,
        title: item.title,
      );
    } else {
      entity = await PhotoManager.editor.saveImageWithPath(
        file.path,
        title: item.title,
      );
    }
    await purge([trashId]);
    return entity;
  }

  /// 彻底删除：仅清回收站本地文件，不再留存
  Future<void> purge(List<String> trashIds) async {
    for (final id in trashIds) {
      final dir = await _itemDir(id);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }
}
