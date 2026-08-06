import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/models/photo_meta.dart';

/// 封装 photo_manager：分页读相册、缩略图、原图、删除、写入。
class GalleryService {
  GalleryService._();
  static final GalleryService instance = GalleryService._();

  /// 申请相册权限（需要完整访问以便读写删除）
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth || state.hasAccess;
  }

  /// 分页拉取图片元数据（按创建时间倒序）
  Future<({List<PhotoMeta> list, int total})> listPhotos({
    required int page,
    required int pageSize,
  }) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (paths.isEmpty) {
      return (list: <PhotoMeta>[], total: 0);
    }

    final album = paths.first;
    final total = await album.assetCountAsync;
    final assets = await album.getAssetListPaged(page: page, size: pageSize);
    final list = assets
        .map(
          (a) => PhotoMeta(
            id: a.id,
            width: a.width,
            height: a.height,
            createTimeMs: a.createDateTime.millisecondsSinceEpoch,
            mimeType: a.mimeType,
            title: a.title,
          ),
        )
        .toList();
    return (list: list, total: total);
  }

  /// 按 id 查找资源
  Future<AssetEntity?> findAsset(String photoId) async {
    return AssetEntity.fromId(photoId);
  }

  /// 缩略图二进制（用于 PC 网格）
  Future<Uint8List?> getThumbnail(String photoId, {int size = 256}) async {
    final asset = await findAsset(photoId);
    if (asset == null) return null;
    return asset.thumbnailDataWithSize(
      ThumbnailSize(size, size),
      quality: 80,
    );
  }

  /// 原图文件（供 HTTPS 流式写出，避免整文件进内存）
  Future<File?> getOriginalFile(String photoId) async {
    final asset = await findAsset(photoId);
    if (asset == null) return null;
    return asset.originFile;
  }

  /// 批量删除系统相册照片，返回实际删除的 id
  Future<List<String>> deletePhotos(List<String> photoIds) async {
    if (photoIds.isEmpty) return const [];
    final ids = <String>[];
    for (final id in photoIds) {
      final e = await findAsset(id);
      if (e != null) ids.add(e.id);
    }
    if (ids.isEmpty) return const [];
    return PhotoManager.editor.deleteWithIds(ids);
  }

  /// 将上传临时文件写入系统相册
  Future<AssetEntity?> saveImageFile(File file, {String? title}) async {
    return PhotoManager.editor.saveImageWithPath(
      file.path,
      title: title ?? p.basename(file.path),
    );
  }

  /// 创建上传临时目录
  Future<Directory> ensureUploadTempDir() async {
    final root = await getTemporaryDirectory();
    final dir = Directory(p.join(root.path, 'photolink_upload'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
