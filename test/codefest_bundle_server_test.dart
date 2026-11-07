import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/util/codefest_bundle_server.dart';

class RealLoopbackHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bundle rejects tampered assets and traversal paths', () {
    List<int> fixture(String key, String digest) => gzip.encode(
      utf8.encode(
        jsonEncode({
          'schema': 1,
          'files': {
            key: {
              'data': base64Encode([1, 2]),
              'sha256': digest,
            },
          },
        }),
      ),
    );
    final valid = sha256.convert([1, 2]).toString();
    expect(
      CodefestBundleServer.decode(fixture('/index.html', valid))['/index.html'],
      [1, 2],
    );
    expect(
      () => CodefestBundleServer.decode(fixture('/index.html', 'bad')),
      throwsFormatException,
    );
    expect(
      () => CodefestBundleServer.decode(fixture('/../index.html', valid)),
      throwsFormatException,
    );
  });
  test(
    'bundled mobile entry and JS are served from loopback without development computer',
    () => HttpOverrides.runWithHttpOverrides(() async {
      await CodefestBundleServer.start();
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          Uri.parse('${CodefestBundleServer.origin}/station-map'),
        )).close();
        expect(response.statusCode, 200);
        expect(
          response.headers.value('content-security-policy'),
          contains("connect-src 'none'"),
        );
        final html = await utf8.decoder.bind(response).join();
        expect(html, contains('<div id="app">'));
        final script = RegExp(r'src="(/js/[^\"]+)"').firstMatch(html);
        expect(script, isNotNull);
        final asset = await (await client.getUrl(
          Uri.parse('${CodefestBundleServer.origin}${script!.group(1)}'),
        )).close();
        expect(asset.statusCode, 200);
        await asset.drain<void>();
        final post = await (await client.postUrl(
          Uri.parse('${CodefestBundleServer.origin}/'),
        )).close();
        expect(post.statusCode, 405);
        await post.drain<void>();
      } finally {
        client.close(force: true);
        await CodefestBundleServer.close();
      }
    }, RealLoopbackHttp()),
  );
}
