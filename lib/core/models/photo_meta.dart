/// 媒体类型：与 PC / API 约定一致（image | video）
class MediaKind {
  static const image = 'image';
  static const video = 'video';

  /// 解析查询参数；非法值回退为图片（兼容旧 PC）
  static String normalize(String? raw) {
    final v = (raw ?? image).trim().toLowerCase();
    if (v == video || v == 'videos') return video;
    if (v == 'all' || v == 'common') return 'all';
    return image;
  }
}

/// 相册媒体元数据（仅元数据，不含二进制）
class PhotoMeta {
  const PhotoMeta({
    required this.id,
    required this.width,
    required this.height,
    required this.createTimeMs,
    this.mimeType,
    this.title,
    this.albumId,
    this.albumName,
    this.mediaType = MediaKind.image,
    this.durationMs = 0,
    this.sizeBytes = 0,
  });

  final String id;
  final int width;
  final int height;
  final int createTimeMs;
  final String? mimeType;
  final String? title;
  final String? albumId;
  final String? albumName;

  /// image / video
  final String mediaType;

  /// 视频时长（毫秒）；图片为 0
  final int durationMs;

  /// 原文件占用字节数（来自系统相册 fileSize）
  final int sizeBytes;

  bool get isVideo => mediaType == MediaKind.video;

  /// 人类可读的文件大小（B / KB / MB / GB）
  String get sizeLabel => formatFileSize(sizeBytes);

  Map<String, dynamic> toJson() => {
        'id': id,
        'width': width,
        'height': height,
        'createTimeMs': createTimeMs,
        'mimeType': mimeType,
        'title': title,
        'albumId': albumId,
        'albumName': albumName,
        'mediaType': mediaType,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      };

  factory PhotoMeta.fromJson(Map<String, dynamic> json) {
    final mime = json['mimeType']?.toString();
    final rawType = json['mediaType']?.toString();
    // 旧端无 mediaType 时，用 mime 推断
    final mediaType = rawType != null && rawType.isNotEmpty
        ? MediaKind.normalize(rawType)
        : (mime != null && mime.startsWith('video/')
            ? MediaKind.video
            : MediaKind.image);
    return PhotoMeta(
      id: json['id']?.toString() ?? '',
      width: int.tryParse('${json['width']}') ?? 0,
      height: int.tryParse('${json['height']}') ?? 0,
      createTimeMs: int.tryParse('${json['createTimeMs']}') ?? 0,
      mimeType: mime,
      title: json['title']?.toString(),
      albumId: json['albumId']?.toString(),
      albumName: json['albumName']?.toString(),
      mediaType: mediaType == 'all' ? MediaKind.image : mediaType,
      durationMs: int.tryParse('${json['durationMs']}') ?? 0,
      sizeBytes: int.tryParse('${json['sizeBytes']}') ?? 0,
    );
  }
}

/// 将字节数格式化为 B / KB / MB / GB
String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return '${kb >= 100 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
