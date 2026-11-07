// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/foundation.dart';

class CodefestScanSession extends ValueNotifier<Map<String, Object>> {
  CodefestScanSession(this.sessionId, this.onEvent)
    : super(const {
        'title': '導航目的地',
        'floor': '尚未定位',
        'instruction': '請將相機對準定位碼。有效碼會更新位置，不會關閉相機。',
        'nextLabel': '確認下一步',
        'canAdvance': false,
      });
  final String sessionId;
  final void Function(Map<String, Object?>) onEvent;
  bool closing = false;
  String? _lastPayload;
  int _sequence = 0;

  void emit(String event, [Map<String, Object?> data = const {}]) {
    onEvent({
      'sessionId': sessionId,
      'seq': _sequence++,
      'event': event,
      ...data,
    });
  }

  bool acceptPayload(String payload) {
    if (closing ||
        payload.isEmpty ||
        utf8.encode(payload).length > 1024 ||
        payload == _lastPayload)
      return false;
    _lastPayload = payload;
    emit('detected', {'payload': payload});
    return true;
  }

  void allowSameCodeAgain() {
    _lastPayload = null;
  }

  void updateGuidance(Map message) {
    if (closing) return;
    final next = Map<String, Object>.from(value);
    for (final entry in const {
      'title': 80,
      'floor': 40,
      'instruction': 2000,
      'nextLabel': 80,
    }.entries) {
      final text = message[entry.key];
      if (text is String)
        next[entry.key] = String.fromCharCodes(text.runes.take(entry.value));
    }
    next['canAdvance'] = message['canAdvance'] == true;
    value = next;
  }

  void requestClose() {
    if (!closing) {
      closing = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    closing = true;
    _lastPayload = null;
    super.dispose();
  }
}
