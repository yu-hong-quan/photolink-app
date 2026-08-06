/// PhotoLink 全局常量（与 PC 端保持一致）
class PhotoLinkConst {
  PhotoLinkConst._();

  /// 手机端相册 HTTPS 服务端口
  static const int port = 53317;

  /// PC 端配对服务端口（App 扫 PC 二维码后向此端口回传本机地址）
  static const int pairPort = 53318;

  /// mDNS 服务类型（Bonjour/NSD）
  static const String mdnsType = '_photolink._tcp';

  /// 产品名
  static const String appName = 'PhotoLink';

  /// 中文简称
  static const String appNameZh = '图联';

  /// 默认分页大小
  static const int defaultPageSize = 60;
}
