import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/codefest_ai/gemma_release.dart';

void main() {
  Map<String, dynamic> fixture() => {
    'schema': 1,
    'available': true,
    'source': GemmaRelease.officialSource,
    'revision': GemmaRelease.revision,
    'size': GemmaRelease.size,
    'download_url': GemmaRelease.download,
    'sha256': GemmaRelease.expectedDigest,
    'agreement': 'test agreement',
    'policy': 'test policy',
    'notice': 'test notice',
  };
  test('pins original model, approved team HTTPS URL and embedded hash', () {
    expect(GemmaRelease.parse(fixture()).available, true);
    for (final entry in {
      'source': 'https://mirror.example/model',
      'revision': 'other',
      'size': 1,
      'download_url':
          'http://home.yoyo899843.com/models/gemma3-1b-it-int4.litertlm',
      'sha256': 'bad',
      'policy': '',
    }.entries) {
      expect(
        () => GemmaRelease.parse({...fixture(), entry.key: entry.value}),
        throwsFormatException,
      );
    }
  });
  test('unpublished release stays unavailable without a fabricated hash', () {
    final release = GemmaRelease.parse({
      ...fixture(),
      'available': false,
      'sha256': null,
    });
    expect(release.available, false);
    expect(release.digest, null);
  });
}
