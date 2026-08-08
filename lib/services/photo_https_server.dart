import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';
import '../core/models/photo_meta.dart';
import 'delete_confirm_bridge.dart';
import 'gallery_service.dart';
import 'trash_service.dart';

/// 手机端 HTTPS 相册 API 服务（Shelf + 自签名证书）
class PhotoHttpsServer {
  PhotoHttpsServer({
    required this.deviceInfo,
    this.onClientActivity,
  });

  DeviceInfoModel deviceInfo;
  HttpServer? _server;

  /// PC 访问业务接口时回调（携带远端 IP，用于首页从「等待连接」切到「已连接」）
  final void Function(String? remoteIp)? onClientActivity;

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;

  /// 启动 53317 端口 HTTPS 服务
  Future<void> start() async {
    if (_server != null) return;

    // 从 assets 加载自签名证书，供局域网 TLS 使用
    final certData = await rootBundle.load('assets/certs/cert.pem');
    final keyData = await rootBundle.load('assets/certs/key.pem');
    final context = SecurityContext()
      ..useCertificateChainBytes(certData.buffer.asUint8List())
      ..usePrivateKeyBytes(keyData.buffer.asUint8List());

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(_buildRouter().call);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      PhotoLinkConst.port,
      securityContext: context,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Router _buildRouter() {
    final router = Router();

    router.get('/api/device/info', (Request request) {
      return _json(deviceInfo.toJson());
    });

    // 分页媒体元数据：只返回 JSON；支持 albumId + mediaType(image|video|all)
    router.get('/api/gallery/list', (Request request) async {
      final page =
          int.tryParse(request.url.queryParameters['page'] ?? '0') ?? 0;
      final pageSize = int.tryParse(
            request.url.queryParameters['pageSize'] ??
                '${PhotoLinkConst.defaultPageSize}',
          ) ??
          PhotoLinkConst.defaultPageSize;
      final albumId = request.url.queryParameters['albumId'];
      // 默认 image，兼容旧 PC；新 PC 会显式传 video
      final mediaType = MediaKind.normalize(
        request.url.queryParameters['mediaType'],
      );
      final result = await GalleryService.instance.listPhotos(
        page: page,
        pageSize: pageSize,
        albumId: albumId,
        mediaType: mediaType,
      );
      return _json({
        'page': page,
        'pageSize': pageSize,
        'total': result.total,
        'mediaType': mediaType,
        'list': result.list.map((e) => e.toJson()).toList(),
      });
    });

    router.get('/api/gallery/albums', (Request request) async {
      final mediaType = MediaKind.normalize(
        request.url.queryParameters['mediaType'],
      );
      final albums = await GalleryService.instance.listAlbums(
        mediaType: mediaType,
      );
      return _json({
        'mediaType': mediaType,
        'list': albums.map((e) => e.toJson()).toList(),
      });
    });

    router.get(
      '/api/gallery/thumbnail/<photoId>',
      (Request request, String photoId) async {
        final bytes =
            await GalleryService.instance.getThumbnail(Uri.decodeComponent(photoId));
        if (bytes == null) {
          return Response.notFound('thumbnail not found');
        }
        return Response.ok(
          bytes,
          headers: {
            'Content-Type': 'image/jpeg',
            'Cache-Control': 'public, max-age=86400',
          },
        );
      },
    );

    // 原图/原视频：以文件流响应，避免整文件读入内存
    router.get(
      '/api/gallery/original/<photoId>',
      (Request request, String photoId) async {
        final file = await GalleryService.instance
            .getOriginalFile(Uri.decodeComponent(photoId));
        if (file == null || !await file.exists()) {
          return Response.notFound('original not found');
        }
        final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
        final length = await file.length();
        return Response.ok(
          file.openRead(),
          headers: {
            'Content-Type': mime,
            'Content-Length': '$length',
            'Content-Disposition':
                'attachment; filename="${p.basename(file.path)}"',
          },
        );
      },
    );

    // 软删除 → App 前台确认（可预览全部图）→ 进回收站
    router.post('/api/gallery/delete', (Request request) async {
      final body = await request.readAsString();
      final decoded = jsonDecode(body);
      final ids = <String>[];
      if (decoded is List) {
        ids.addAll(decoded.map((e) => e.toString()));
      } else if (decoded is Map && decoded['photoIds'] is List) {
        ids.addAll((decoded['photoIds'] as List).map((e) => e.toString()));
      }
      if (ids.isEmpty) {
        return _json({'success': false, 'error': 'empty photoIds'}, status: 400);
      }

      // 阻塞等待手机用户浏览全部图片并二次确认
      final approved =
          await DeleteConfirmBridge.instance.requestConfirm(ids);
      if (!approved) {
        return _json(
          {
            'success': false,
            'cancelled': true,
            'error': '用户取消或超时未确认删除',
          },
          status: 403,
        );
      }

      final deleted = await TrashService.instance.softDelete(ids);
      return _json({
        'success': true,
        'deleted': deleted,
        'requested': ids.length,
        'softDelete': true,
      });
    });

    router.post('/api/gallery/rename', (Request request) async {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final photoId = body['photoId']?.toString() ?? '';
      final title = body['title']?.toString() ?? '';
      await GalleryService.instance.renamePhoto(photoId, title);
      return _json({'success': true, 'photoId': photoId, 'title': title});
    });

    router.post('/api/gallery/categorize', (Request request) async {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final albumName = body['albumName']?.toString() ?? '';
      final ids = (body['photoIds'] as List? ?? []).map((e) => e.toString()).toList();
      await GalleryService.instance.categorizePhotos(
        photoIds: ids,
        albumName: albumName,
      );
      return _json({
        'success': true,
        'albumName': albumName,
        'count': ids.length,
      });
    });

    // —— 回收站 ——
    router.get('/api/trash/list', (Request request) async {
      final list = await TrashService.instance.list();
      return _json({'list': list.map((e) => e.toJson()).toList()});
    });

    router.get('/api/trash/thumbnail/<trashId>', (Request request, String trashId) async {
      final file =
          await TrashService.instance.thumbFile(Uri.decodeComponent(trashId));
      if (file == null) return Response.notFound('not found');
      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': 'image/jpeg',
          'Content-Length': '${await file.length()}',
        },
      );
    });

    router.get('/api/trash/original/<trashId>', (Request request, String trashId) async {
      final file = await TrashService.instance
          .originalFile(Uri.decodeComponent(trashId));
      if (file == null) return Response.notFound('not found');
      final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': mime,
          'Content-Length': '${await file.length()}',
        },
      );
    });

    router.post('/api/trash/restore', (Request request) async {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final ids = (body['trashIds'] as List? ?? []).map((e) => e.toString()).toList();
      final restored = <String>[];
      for (final id in ids) {
        final entity = await TrashService.instance.restore(id);
        if (entity != null) restored.add(entity.id);
      }
      return _json({'success': true, 'restored': restored});
    });

    // 彻底删除：清回收站本地文件，PC 端也不再留存
    router.post('/api/trash/purge', (Request request) async {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final ids = (body['trashIds'] as List? ?? []).map((e) => e.toString()).toList();
      await TrashService.instance.purge(ids);
      return _json({'success': true, 'purged': ids});
    });

    // 流式上传：边收边写临时文件，再按扩展名写入系统相册（图/视频）
    router.post('/api/gallery/upload', (Request request) async {
      final fileName = request.headers['x-filename'] ??
          request.headers['X-Filename'] ??
          'upload_${const Uuid().v4()}.jpg';
      final safeName = p.basename(Uri.decodeComponent(fileName));
      final tempDir = await GalleryService.instance.ensureUploadTempDir();
      final tempFile = File(p.join(tempDir.path, '${const Uuid().v4()}_$safeName'));
      final sink = tempFile.openWrite();
      try {
        await for (final chunk in request.read()) {
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        final entity = await GalleryService.instance.saveMediaFile(
          tempFile,
          title: safeName,
        );
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (entity == null) {
          return _json({'success': false, 'message': '写入相册失败'}, status: 500);
        }
        final isVideo = entity.type == AssetType.video;
        return _json({
          'success': true,
          'photoId': entity.id,
          'fileName': safeName,
          'mediaType': isVideo ? MediaKind.video : MediaKind.image,
        });
      } catch (e) {
        try {
          await sink.close();
        } catch (_) {}
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        return _json({'success': false, 'message': '$e'}, status: 500);
      }
    });

    router.get('/health', (Request request) => Response.ok('ok'));

    return router;
  }

  Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        // 任意业务请求视为 PC 活跃，驱动首页连接状态
        _emitClientActivity(request);
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  /// 从 shelf_io 上下文取出远端 IP 并通知 UI
  void _emitClientActivity(Request request) {
    final cb = onClientActivity;
    if (cb == null) return;
    String? remoteIp;
    final info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) {
      remoteIp = info.remoteAddress.address;
    }
    cb(remoteIp);
  }

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers':
        'Origin, Content-Type, X-Filename, Content-Type',
  };

  Response _json(Object data, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}
