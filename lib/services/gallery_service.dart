import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/models/photo_meta.dart';
import 'photo_meta_store.dart';

/// 相册分类摘要
class AlbumInfo {
  const AlbumInfo({
    required this.id,
    required this.name,
    required this.count,
    required this.isAll,
  });

  final String id;
  final String name;
  final int count;
  final bool isAll;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'count': count,
        'isAll': isAll,
      };
}

/// 封装 photo_manager：分页读相册、缩略图、原图、软删、归类、重命名。
class GalleryService {
  GalleryService._();
  static final GalleryService instance = GalleryService._();

  FilterOptionGroup get _newestFirstFilter {
    final group = FilterOptionGroup();
    group.addOrderOption(
      const OrderOption(type: OrderOptionType.createDate, asc: false),
    );
    return group;
  }

  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth || state.hasAccess;
  }

  /// 分页拉取图片元数据（强制按创建时间倒序，最近的在前）
  Future<({List<PhotoMeta> list, int total})> listPhotos({
    required int page,
    required int pageSize,
    String? albumId,
  }) async {
    final album = await _resolveAlbum(albumId);
    if (album == null) {
      return (list: <PhotoMeta>[], total: 0);
    }

    final total = await album.assetCountAsync;
    final assets = await album.getAssetListPaged(page: page, size: pageSize);
    // 兜底再按创建时间倒序（部分机型 filter 不生效）
    assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    final list = <PhotoMeta>[];
    for (final a in assets) {
      final overrideTitle = await PhotoMetaStore.instance.getDisplayTitle(a.id);
      final albumName = await PhotoMetaStore.instance.getAlbumName(a.id);
      list.add(
        PhotoMeta(
          id: a.id,
          width: a.width,
          height: a.height,
          createTimeMs: a.createDateTime.millisecondsSinceEpoch,
          mimeType: a.mimeType,
          title: overrideTitle ?? a.title,
          albumId: albumId,
          albumName: albumName,
        ),
      );
    }
    return (list: list, total: total);
  }

  Future<AssetPathEntity?> _resolveAlbum(String? albumId) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: albumId == null || albumId.isEmpty,
      filterOption: _newestFirstFilter,
    );
    if (paths.isEmpty) return null;
    if (albumId == null || albumId.isEmpty) {
      return paths.firstWhere((e) => e.isAll, orElse: () => paths.first);
    }
    for (final path in paths) {
      if (path.id == albumId) return path;
    }
    // onlyAll=true 时可能拿不到子相册，再拉一遍
    final all = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
      filterOption: _newestFirstFilter,
    );
    for (final path in all) {
      if (path.id == albumId) return path;
    }
    return null;
  }

  Future<List<AlbumInfo>> listAlbums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
      filterOption: _newestFirstFilter,
    );
    final result = <AlbumInfo>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      result.add(
        AlbumInfo(
          id: path.id,
          name: path.name,
          count: count,
          isAll: path.isAll,
        ),
      );
    }
    result.sort((a, b) {
      if (a.isAll != b.isAll) return a.isAll ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  Future<AssetEntity?> findAsset(String photoId) async {
    return AssetEntity.fromId(photoId);
  }

  Future<Uint8List?> getThumbnail(String photoId, {int size = 256}) async {
    final asset = await findAsset(photoId);
    if (asset == null) return null;
    return asset.thumbnailDataWithSize(
      ThumbnailSize(size, size),
      quality: 80,
    );
  }

  Future<File?> getOriginalFile(String photoId) async {
    final asset = await findAsset(photoId);
    if (asset == null) return null;
    return asset.originFile;
  }

  /// 硬删（回收站彻底删除后不再调用；一般走 TrashService.softDelete）
  Future<List<String>> deletePhotos(List<String> photoIds) async {
    if (photoIds.isEmpty) return const [];
    final ids = <String>[];
    for (final id in photoIds) {
      final e = await findAsset(id);
      if (e != null) ids.add(e.id);
    }
    if (ids.isEmpty) return const [];
    final deleted = await PhotoManager.editor.deleteWithIds(ids);
    for (final id in deleted) {
      await PhotoMetaStore.instance.remove(id);
    }
    return deleted;
  }

  /// 重命名：写入应用侧显示名（系统层文件名平台限制多，统一用显示名）
  Future<void> renamePhoto(String photoId, String newTitle) async {
    final title = newTitle.trim();
    if (title.isEmpty) throw Exception('名称不能为空');
    final asset = await findAsset(photoId);
    if (asset == null) throw Exception('照片不存在');
    await PhotoMetaStore.instance.setDisplayTitle(photoId, title);
  }

  /// 归类到相册：写入元数据并同步到系统相册（Android/iOS 尽力而为）
  Future<void> categorizePhotos({
    required List<String> photoIds,
    required String albumName,
  }) async {
    final name = albumName.trim();
    if (name.isEmpty) throw Exception('分类名称不能为空');
    if (photoIds.isEmpty) return;

    AssetPathEntity? target = await _findAlbumByName(name);
    target ??= await _createAlbum(name);

    for (final id in photoIds) {
      final asset = await findAsset(id);
      if (asset == null) continue;
      await PhotoMetaStore.instance.setAlbumName(id, name);
      if (target != null) {
        try {
          await PhotoManager.editor.copyAssetToPath(
            asset: asset,
            pathEntity: target,
          );
        } catch (_) {
          // Android 部分机型 copy 失败时尝试 move
          if (Platform.isAndroid) {
            try {
              await PhotoManager.editor.android.moveAssetToAnother(
                entity: asset,
                target: target,
              );
            } catch (_) {
              try {
                await PhotoManager.editor.android.moveAssetsToPath(
                  entities: [asset],
                  targetPath: 'Pictures/$name',
                );
              } catch (_) {}
            }
          }
        }
      } else if (Platform.isAndroid) {
        try {
          await PhotoManager.editor.android.moveAssetsToPath(
            entities: [asset],
            targetPath: 'Pictures/$name',
          );
        } catch (_) {}
      }
    }
  }

  Future<AssetPathEntity?> _findAlbumByName(String name) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
    );
    for (final path in paths) {
      if (!path.isAll && path.name == name) return path;
    }
    return null;
  }

  Future<AssetPathEntity?> _createAlbum(String name) async {
    if (Platform.isIOS || Platform.isMacOS) {
      return PhotoManager.editor.darwin.createAlbum(name);
    }
    // Android 无直接 createAlbum：通过 relativePath 写入一张占位图再删除过于危险；
    // 返回 null，由调用方用 moveAssetsToPath('Pictures/$name') 隐式建目录。
    return null;
  }

  Future<AssetEntity?> saveImageFile(File file, {String? title}) async {
    return PhotoManager.editor.saveImageWithPath(
      file.path,
      title: title ?? p.basename(file.path),
    );
  }

  Future<Directory> ensureUploadTempDir() async {
    final root = await getTemporaryDirectory();
    final dir = Directory(p.join(root.path, 'photolink_upload'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
