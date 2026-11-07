import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/codefest_ai/gemma_model_store.dart';

void main() {
  test('only HTTPS official HF hosts and default TLS port are accepted', () {
    expect(
      GemmaModelStore.approvedUri(Uri.parse(GemmaModelStore.source)),
      true,
    );
    expect(
      GemmaModelStore.approvedUri(
        Uri.parse('https://cas-bridge.xethub.hf.co/blob'),
      ),
      true,
    );
    for (final url in [
      'http://huggingface.co/blob',
      'https://huggingface.co.evil.example/blob',
      'https://mirror.example/blob',
      'https://user:secret@huggingface.co/blob',
      'https://huggingface.co:8000/blob',
    ]) {
      expect(GemmaModelStore.approvedUri(Uri.parse(url)), false);
    }
  });
  test('pointer binds exact model size and sha256, refuses unrelated content', () {
    final digest = 'a' * 64;
    final pointer =
        'version https://git-lfs.github.com/spec/v1\noid sha256:$digest\nsize 584417280\n';
    expect(GemmaModelStore.parsePointer(pointer), digest);
    for (final invalid in [
      pointer.replaceFirst('584417280', '10'),
      pointer.replaceFirst(digest, 'bad'),
      '<html>login</html>',
      '$pointer\nextra',
    ]) {
      expect(
        () => GemmaModelStore.parsePointer(invalid),
        throwsFormatException,
      );
    }
  });
  test('license gate runs before any download', () async {
    final store = GemmaModelStore();
    await expectLater(
      store.install(termsAccepted: false, token: '', onProgress: (_) {}),
      throwsStateError,
    );
    store.cancel();
  });
}
