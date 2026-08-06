import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';
import 'gallery_service.dart';

/// 手机端 HTTPS 相册 API 服务（Shelf + 自签名证书）
class PhotoHttpsServer {
  PhotoHttpsServer({required this.deviceInfo});

  DeviceInfoModel deviceInfo;
  HttpServer? _server;

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

    // 分页相册元数据：只返回 JSON，不返回图片二进制
    router.get('/api/gallery/list', (Request request) async {
      final page =
          int.tryParse(request.url.queryParameters['page'] ?? '0') ?? 0;
      final pageSize = int.tryParse(
            request.url.queryParameters['pageSize'] ??
                '${PhotoLinkConst.defaultPageSize}',
          ) ??
          PhotoLinkConst.defaultPageSize;
      final result = await GalleryService.instance.listPhotos(
        page: page,
        pageSize: pageSize,
      );
      return _json({
        'page': page,
        'pageSize': pageSize,
        'total': result.total,
        'list': result.list.map((e) => e.toJson()).toList(),
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

    // 原图：以文件流响应，避免整图读入内存
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

    router.post('/api/gallery/delete', (Request request) async {
      final body = await request.readAsString();
      final decoded = jsonDecode(body);
      final ids = <String>[];
      if (decoded is List) {
        ids.addAll(decoded.map((e) => e.toString()));
      } else if (decoded is Map && decoded['photoIds'] is List) {
        ids.addAll((decoded['photoIds'] as List).map((e) => e.toString()));
      }
      final deleted = await GalleryService.instance.deletePhotos(ids);
      return _json({
        'success': true,
        'deleted': deleted,
        'requested': ids.length,
      });
    });

    // 流式上传：边收边写临时文件，再写入系统相册
    router.post('/api/gallery/upload', (Request request) async {
      final fileName = request.headers['x-filename'] ??
          request.headers['X-Filename'] ??
          'upload_${const Uuid().v4()}.jpg';
      final safeName = p.basename(Uri.decodeComponent(fileName));
      final tempDir = await GalleryService.instance.ensureUploadTempDir();
      final tempFile = File(p.join(tempDir.path, '${const Uuid().v4()}_$safeName'));
      final sink = tempFile.openWrite();
      try {
        await request.read().pipe(sink);
        await sink.flush();
        await sink.close();
        final entity = await GalleryService.instance.saveImageFile(
          tempFile,
          title: safeName,
        );
        // 写入相册后清理临时文件
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (entity == null) {
          return _json({'success': false, 'message': '写入相册失败'}, status: 500);
        }
        return _json({
          'success': true,
          'photoId': entity.id,
          'fileName': safeName,
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
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };
    };
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
