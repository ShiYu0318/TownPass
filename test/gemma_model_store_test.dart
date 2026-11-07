import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/codefest_ai/gemma_model_store.dart';

void main() {
  test('only approved team HTTPS host and default TLS port are accepted', () {
    expect(
      GemmaModelStore.approvedUri(
        Uri.parse(
          'https://home.yoyo899843.com/models/gemma3-1b-it-int4.litertlm',
        ),
      ),
      true,
    );
    expect(
      GemmaModelStore.approvedUri(
        Uri.parse('https://home.yoyo899843.com/models/receipt.json'),
      ),
      true,
    );
    for (final url in [
      'http://home.yoyo899843.com/blob',
      'https://huggingface.co/blob',
      'https://huggingface.co.evil.example/blob',
      'https://mirror.example/blob',
      'https://user:secret@home.yoyo899843.com/blob',
      'https://home.yoyo899843.com:8000/blob',
    ]) {
      expect(GemmaModelStore.approvedUri(Uri.parse(url)), false);
    }
  });
  test('license gate runs before any download', () async {
    final store = GemmaModelStore();
    await expectLater(
      store.install(termsAccepted: false, onProgress: (_) {}),
      throwsStateError,
    );
    store.cancel();
  });
}
