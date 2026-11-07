// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/codefest_scan/codefest_scan_session.dart';
import 'package:town_pass/page/codefest_scan/codefest_scan_view.dart';
import 'package:town_pass/util/web_message_handler/tp_web_message_handler.dart';

class CodefestScanMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'qr_scan_session';
  CodefestScanSession? _active;
  static const _origins = {
    'http://127.0.0.1:8082',
    'http://localhost:8082',
    'http://home.yoyo899843.com:8000',
  };
  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage replyWebMessage)? onReply,
  }) async {
    final uri = Uri.tryParse(sourceOrigin?.toString() ?? '');
    if (!isMainFrame ||
        uri == null ||
        !uri.hasAuthority ||
        !_origins.contains(uri.origin) ||
        message is! Map)
      return;
    final id = message['sessionId'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) return;
    void reply(Map<String, Object?> data) {
      try {
        onReply?.call(replyWebMessage(data: data));
      } catch (_) {
        if (_active?.sessionId == id) _active?.requestClose();
      }
    }

    switch (message['action']) {
      case 'capabilities':
        reply({
          'sessionId': id,
          'event': 'capabilities',
          'continuous': true,
          'protocol': 1,
        });
        return;
      case 'start':
        if (_active != null) {
          reply({'sessionId': id, 'seq': 0, 'event': 'error', 'code': 'busy'});
          return;
        }
        final session = CodefestScanSession(id, reply);
        _active = session;
        if (message['guidance'] is Map)
          session.updateGuidance(message['guidance'] as Map);
        session.emit('started');
        try {
          await Get.to(
            () => CodefestScanView(session: session),
            routeName: '/codefest_scan_$id',
          );
        } finally {
          session.requestClose();
          session.emit('closed');
          if (identical(_active, session)) _active = null;
          session.dispose();
        }
        return;
      case 'update':
        if (_active?.sessionId == id && message['guidance'] is Map)
          _active?.updateGuidance(message['guidance'] as Map);
        return;
      case 'stop':
        if (_active?.sessionId == id) _active?.requestClose();
        return;
    }
  }
}
