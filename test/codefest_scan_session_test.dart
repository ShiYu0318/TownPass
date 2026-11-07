import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/codefest_scan/codefest_scan_session.dart';

void main() {
  test('one session streams different codes without closing, suppresses repeated frames, permits explicit rescan', () {
    final events = <Map<String, Object?>>[];
    final session = CodefestScanSession('test', events.add);
    expect(session.acceptPayload('a'), isTrue);
    expect(session.acceptPayload('a'), isFalse);
    expect(session.acceptPayload('b'), isTrue);
    expect(session.closing, isFalse);
    session.allowSameCodeAgain();
    expect(session.acceptPayload('b'), isTrue);
    expect(events.map((e) => e['payload']), ['a', 'b', 'b']);
    expect(events.map((e) => e['seq']), [0, 1, 2]);
    session.requestClose();
    expect(session.acceptPayload('c'), isFalse);
    session.dispose();
  });
  test('rejects oversized UTF-8 and keeps typed bounded guidance', () {
    final session = CodefestScanSession('test', (_) {});
    expect(session.acceptPayload('🙂' * 300), isFalse);
    session.updateGuidance({
      'title': 'x' * 100,
      'instruction': 42,
      'canAdvance': 'yes',
    });
    expect((session.value['title'] as String).length, 80);
    expect(session.value['instruction'], isA<String>());
    expect(session.value['canAdvance'], isFalse);
    session.dispose();
  });
}
