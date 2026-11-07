// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class CodefestBundleServer {
  static const origin = 'http://127.0.0.1:8766';
  static HttpServer? _server;
  static Future<void>? _starting;
  static const pages = {
    '/',
    '/station-map',
    '/navigation-demo',
    '/meet',
    '/test',
  };
  static Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  static String get listeningOrigin =>
      'http://127.0.0.1:${_server?.port ?? 8766}';
  static Future<void> start({int port = 8766}) async {
    if (_server != null) return;
    if (_starting != null) return _starting;
    _starting = _start(port);
    try {
      await _starting;
    } finally {
      _starting = null;
    }
  }

  static Map<String, Uint8List> decode(List<int> encoded) {
    final document = jsonDecode(utf8.decode(gzip.decode(encoded)));
    if (document is! Map ||
        document['schema'] != 1 ||
        document['files'] is! Map) {
      throw const FormatException('Invalid web bundle');
    }
    final files = <String, Uint8List>{};
    for (final entry in (document['files'] as Map).entries) {
      if (entry.key is! String ||
          !(entry.key as String).startsWith('/') ||
          (entry.key as String).contains('..') ||
          entry.value is! Map) {
        throw const FormatException('Invalid asset path');
      }
      final bytes = base64Decode(entry.value['data'] as String);
      if (sha256.convert(bytes).toString() != entry.value['sha256']) {
        throw const FormatException('Asset digest mismatch');
      }
      files[entry.key] = bytes;
    }
    if (!files.containsKey('/index.html')) {
      throw const FormatException('Missing bundle entry');
    }
    return files;
  }

  static Future<void> _start(int port) async {
    final asset = await rootBundle.load('assets/codefest_web.bundle');
    final files = decode(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _server = server;
    server.listen((request) async {
      final response = request.response;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'",
      );
      if (!{'GET', 'HEAD'}.contains(request.method)) {
        response.statusCode = 405;
        await response.close();
        return;
      }
      final path = pages.contains(request.uri.path)
          ? '/index.html'
          : request.uri.path;
      final content = files[path];
      if (content == null) {
        response.statusCode = 404;
        await response.close();
        return;
      }
      final mime = path.endsWith('.html')
          ? 'text/html; charset=utf-8'
          : path.endsWith('.js')
          ? 'application/javascript; charset=utf-8'
          : path.endsWith('.css')
          ? 'text/css; charset=utf-8'
          : path.endsWith('.svg')
          ? 'image/svg+xml'
          : path.endsWith('.png')
          ? 'image/png'
          : path.endsWith('.ico')
          ? 'image/x-icon'
          : 'application/octet-stream';
      response.headers.set(HttpHeaders.contentTypeHeader, mime);
      response.contentLength = content.length;
      if (request.method != 'HEAD') response.add(content);
      await response.close();
    });
  }
}
