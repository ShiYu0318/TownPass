// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class GemmaModelStore {
  static const fileName = 'gemma3-1b-it-int4.litertlm';
  static const revision = '42d538a932e8d5b12e6b3b455f5572560bd60b2c';
  static const size = 584417280;
  static const source =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/$revision/$fileName';
  static const pointer =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/raw/$revision/$fileName';
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);
  bool _cancelled = false;
  static bool approvedUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (uri.port == 443) &&
      (uri.host == 'huggingface.co' ||
          uri.host.endsWith('.huggingface.co') ||
          uri.host.endsWith('.hf.co'));
  static String parsePointer(String value) {
    final match = RegExp(
      r'^version https://git-lfs.github.com/spec/v1\noid sha256:([a-f0-9]{64})\nsize 584417280\n?$',
    ).firstMatch(value);
    if (match == null) {
      throw const FormatException('Invalid pinned Google artifact pointer');
    }
    return match.group(1)!;
  }

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  Future<HttpClientResponse> _open(String url, String token) async {
    var uri = Uri.parse(url);
    for (var attempt = 0; attempt < 6; attempt++) {
      if (_cancelled || !approvedUri(uri)) {
        throw const HttpException('Unapproved source or cancelled');
      }
      final request = await _client.getUrl(uri);
      request.followRedirects = false;
      if (token.isNotEmpty && uri.host == 'huggingface.co') {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) throw const HttpException('Missing redirect');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException(
          'Official model access failed (${response.statusCode})',
        );
      }
      return response;
    }
    throw const HttpException('Too many redirects');
  }

  Future<void> install({
    required bool termsAccepted,
    required String token,
    required void Function(double) onProgress,
  }) async {
    if (!termsAccepted) throw StateError('Gemma license acceptance required');
    final metadata = await _open(pointer, token);
    final bytes = <int>[];
    await for (final chunk in metadata.timeout(const Duration(seconds: 60))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024) throw const FormatException('Oversized pointer');
    }
    final expected = parsePointer(utf8.decode(bytes));
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/CodefestAI');
    await directory.create(recursive: true);
    final working = await directory.createTemp('.install-');
    final temporary = File('${working.path}/$fileName.part');
    try {
      final response = await _open(source, token);
      var count = 0;
      final output = await temporary.open(mode: FileMode.write);
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          if (_cancelled) throw StateError('Cancelled');
          count += chunk.length;
          if (count > size) throw const FormatException('Oversized model');
          await output.writeFrom(chunk);
          onProgress(count / size);
        }
      } finally {
        await output.close();
      }
      if (_cancelled || count != size) {
        throw const FormatException('Incomplete model');
      }
      final path = temporary.path;
      final digest = await Isolate.run(
        () async => (await sha256.bind(File(path).openRead()).first).toString(),
      );
      if (_cancelled || digest != expected) {
        throw const FormatException('Model digest mismatch');
      }
      await temporary.rename('${directory.path}/$fileName');
      final receipt = File('${working.path}/receipt.json.part');
      await receipt.writeAsString(
        jsonEncode({
          'source': source,
          'sha256': expected,
          'size': size,
          'revision': revision,
          'license': 'Gemma Terms of Use',
        }),
        flush: true,
      );
      await receipt.rename('${directory.path}/receipt.json');
    } finally {
      if (await working.exists()) await working.delete(recursive: true);
      _client.close(force: true);
    }
  }
}
