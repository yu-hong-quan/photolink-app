import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'gallery_service.dart';

/// PC 发起删除时，在 App 前台弹出确认桥接。
/// HTTP 请求会阻塞到用户确认/取消（或超时）。
class DeleteConfirmBridge {
  DeleteConfirmBridge._();
  static final DeleteConfirmBridge instance = DeleteConfirmBridge._();

  /// 由 MaterialApp 注入，用于在任意 isolate 回调里弹窗
  GlobalKey<NavigatorState>? navigatorKey;

  Completer<bool>? _busy;

  /// 请求用户确认删除；返回 true 才允许继续软删
  Future<bool> requestConfirm(List<String> photoIds) async {
    if (photoIds.isEmpty) return false;
    // 已有确认中：拒绝并发删除，避免叠多个弹窗
    if (_busy != null) return false;

    final nav = navigatorKey?.currentState;
    final ctx = nav?.overlay?.context ?? navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return false;

    final completer = Completer<bool>();
    _busy = completer;

    // 超时自动拒绝，避免 PC 请求一直挂起
    Timer(const Duration(minutes: 2), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    try {
      // 等下一帧，确保 overlay 可用
      await Future<void>.delayed(Duration.zero);
      final overlayCtx = navigatorKey?.currentState?.overlay?.context ?? ctx;
      if (!overlayCtx.mounted) {
        if (!completer.isCompleted) completer.complete(false);
      } else {
        final ok = await showDialog<bool>(
          context: overlayCtx,
          barrierDismissible: false,
          builder: (_) => _DeleteConfirmDialog(photoIds: photoIds),
        );
        if (!completer.isCompleted) {
          completer.complete(ok == true);
        }
      }
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
    }

    final result = await completer.future;
    _busy = null;
    return result;
  }
}

/// 第一步：浏览全部待删媒体（图片可缩放，视频可点播放）；第二步：再次确认
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({required this.photoIds});

  final List<String> photoIds;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _thumbs = <String, Uint8List?>{};
  /// id → 是否为视频（决定预览方式）
  final _isVideo = <String, bool>{};
  int _previewIndex = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbs();
  }

  Future<void> _loadThumbs() async {
    for (final id in widget.photoIds) {
      try {
        final asset = await GalleryService.instance.findAsset(id);
        final isVideo = asset?.type == AssetType.video;
        final bytes = await GalleryService.instance.getThumbnail(id);
        if (mounted) {
          setState(() {
            _isVideo[id] = isVideo;
            _thumbs[id] = bytes;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isVideo[id] = false;
            _thumbs[id] = null;
          });
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onConfirmTap() async {
    // 第二步：再确认一次，防止误触
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('再次确认删除'),
        content: Text(
          '确认将 ${widget.photoIds.length} 项媒体移入回收站？\n'
          '可在回收站撤回；彻底删除需另行操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (again == true) {
      Navigator.pop(context, true);
    }
  }

  /// 视频：打开内嵌播放器预览；图片：大图已在主区域可缩放
  Future<void> _openVideoPreview(String photoId) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _LocalVideoPreviewDialog(photoId: photoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.photoIds;
    final currentId = ids[_previewIndex.clamp(0, ids.length - 1)];
    final previewBytes = _thumbs[currentId];
    final currentIsVideo = _isVideo[currentId] == true;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: Column(
          children: [
            AppBar(
              title: Text('确认删除（${ids.length} 项）'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                currentIsVideo
                    ? '请滑动/点选查看；点封面可播放预览视频'
                    : '请滑动/点选查看全部媒体，确认无误后再删除',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(12),
                color: Colors.black12,
                child: _loading && previewBytes == null
                    ? const Center(child: CircularProgressIndicator())
                    : previewBytes == null
                        ? const Center(child: Icon(Icons.broken_image_outlined))
                        : currentIsVideo
                            ? _VideoCoverPreview(
                                bytes: previewBytes,
                                onPlay: () => _openVideoPreview(currentId),
                              )
                            : InteractiveViewer(
                                child: Image.memory(
                                  previewBytes,
                                  fit: BoxFit.contain,
                                ),
                              ),
              ),
            ),
            // 全部缩略图列表，便于逐张核对
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: ids.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final id = ids[index];
                  final bytes = _thumbs[id];
                  final selected = index == _previewIndex;
                  final isVideo = _isVideo[id] == true;
                  return GestureDetector(
                    onTap: () => setState(() => _previewIndex = index),
                    child: Container(
                      width: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          bytes == null
                              ? const ColoredBox(
                                  color: Colors.black12,
                                  child: Icon(Icons.image_outlined, size: 20),
                                )
                              : Image.memory(bytes, fit: BoxFit.cover),
                          if (isVideo)
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white70,
                                size: 22,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Text('${_previewIndex + 1} / ${ids.length}'),
                  if (currentIsVideo) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _openVideoPreview(currentId),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('预览视频'),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('拒绝'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _onConfirmTap,
                    child: const Text('确认删除'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 删除确认主预览区：视频封面 + 可点击播放
class _VideoCoverPreview extends StatelessWidget {
  const _VideoCoverPreview({
    required this.bytes,
    required this.onPlay,
  });

  final Uint8List bytes;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.contain),
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white70,
                size: 64,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Text(
                '点击播放预览',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本地原视频播放预览（从相册取 originFile，不走网络）
class _LocalVideoPreviewDialog extends StatefulWidget {
  const _LocalVideoPreviewDialog({required this.photoId});

  final String photoId;

  @override
  State<_LocalVideoPreviewDialog> createState() =>
      _LocalVideoPreviewDialogState();
}

class _LocalVideoPreviewDialogState extends State<_LocalVideoPreviewDialog> {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = await GalleryService.instance.getOriginalFile(widget.photoId);
      if (file == null || !await file.exists()) {
        throw Exception('找不到原视频文件');
      }
      final controller = VideoPlayerController.file(File(file.path));
      await controller.initialize();
      await controller.setLooping(true);
      // 播放状态变化时刷新暂停图标
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('视频预览'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '预览失败：$_error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      : c == null
                          ? const SizedBox.shrink()
                          : Center(
                              child: AspectRatio(
                                aspectRatio: c.value.aspectRatio == 0
                                    ? 16 / 9
                                    : c.value.aspectRatio,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(c),
                                    // 点击切换播放/暂停
                                    Positioned.fill(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          setState(() {
                                            if (c.value.isPlaying) {
                                              c.pause();
                                            } else {
                                              c.play();
                                            }
                                          });
                                        },
                                        child: AnimatedOpacity(
                                          opacity: c.value.isPlaying ? 0 : 1,
                                          duration:
                                              const Duration(milliseconds: 200),
                                          child: const Icon(
                                            Icons.play_circle_outline_rounded,
                                            color: Colors.white70,
                                            size: 56,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
            ),
            if (c != null && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF0B6E6B),
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
