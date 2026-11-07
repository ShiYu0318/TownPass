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
      'guidanceVersion': 1,
      'guidanceToken': 'bounded',
      'title': 'x' * 100,
      'instruction': 42,
      'canAdvance': 'yes',
    });
    expect((session.value['title'] as String).length, 80);
    expect(session.value['instruction'], isA<String>());
    expect(session.value['canAdvance'], isFalse);
    session.dispose();
  });
  test('actions consume displayed guidance and QR invalidates old buttons before web reply', () {
    final events = <Map<String, Object?>>[];
    final session = CodefestScanSession('test', events.add);
    session.updateGuidance({
      'guidanceVersion': 1,
      'guidanceToken': 'old',
      'canAdvance': true,
    });
    expect(session.requestAdvance('old'), isTrue);
    expect(session.requestAdvance('old'), isFalse);
    session.updateGuidance({
      'guidanceVersion': 2,
      'guidanceToken': 'before_qr',
      'canAdvance': true,
    });
    session.acceptPayload('new_anchor');
    expect(session.requestAdvance('before_qr'), isFalse);
    session.updateGuidance({
      'guidanceVersion': 1,
      'guidanceToken': 'old',
      'canAdvance': true,
    });
    expect(session.requestAdvance('old'), isFalse);
    session.updateGuidance({
      'guidanceVersion': 3,
      'guidanceToken': 'after_qr',
      'canAdvance': true,
    });
    expect(session.requestAdvance('after_qr'), isTrue);
    expect(
      events
          .where((e) => e['event'] == 'action')
          .map((e) => e['guidanceToken']),
      ['old', 'after_qr'],
    );
    session.dispose();
  });
}
