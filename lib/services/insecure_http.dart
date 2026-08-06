import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// App 调用 PC 配对接口时信任自签名证书
IOClient createInsecureIoClient() {
  final client = HttpClient();
  // 局域网自签名证书：允许坏证书
  client.badCertificateCallback = (cert, host, port) => true;
  client.connectionTimeout = const Duration(seconds: 8);
  return IOClient(client);
}

Future<http.Response> postJsonInsecure(Uri uri, String body) {
  final io = createInsecureIoClient();
  return io
      .post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      )
      .whenComplete(io.close);
}
