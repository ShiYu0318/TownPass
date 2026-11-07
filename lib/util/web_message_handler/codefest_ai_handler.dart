// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:town_pass/page/codefest_ai/gemma_setup_view.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:town_pass/util/web_message_handler/tp_web_message_handler.dart';

class CodefestAIMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'codefest_ai';
  bool _settingUp = false;
  static const channel = MethodChannel('codefest/on_device_ai');
  static const origins = {
    'http://127.0.0.1:8082',
    'http://localhost:8082',
    'https://home.yoyo899843.com',
  };
  static const locales = {
    'zh-TW',
    'en-US',
    'vi-VN',
    'id-ID',
    'th-TH',
    'ko-KR',
    'ja-JP',
  };
  static bool validId(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage replyWebMessage)? onReply,
  }) async {
    final origin = Uri.tryParse(sourceOrigin?.toString() ?? '');
    if (!isMainFrame ||
        origin == null ||
        !origin.hasAuthority ||
        !origins.contains(origin.origin) ||
        message is! Map ||
        !validId(message['requestId'])) {
      return;
    }
    final id = message['requestId'];
    final action = message['action'];
    if (!{
      'status',
      'setup',
      'generate',
      'voice',
      'stopVoice',
      'cancel',
      'unload',
    }.contains(action)) {
      return;
    }
    final prompt = message['prompt'];
    if (action == 'generate' &&
        (prompt is! String || prompt.trim().isEmpty || prompt.length > 6000)) {
      return;
    }
    if (action == 'cancel' && !validId(message['targetRequestId'])) return;
    if ({'status', 'voice'}.contains(action) &&
        !locales.contains(message['locale'])) {
      return;
    }
    Map result;
    if (action == 'setup') {
      if (_settingUp) {
        onReply?.call(
          replyWebMessage(
            data: {'requestId': id, 'status': 'error', 'code': 'busy'},
          ),
        );
        return;
      }
      _settingUp = true;
      try {
        await channel.invokeMethod('unload');
        await Get.to(() => const GemmaSetupView());
        onReply?.call(
          replyWebMessage(data: {'requestId': id, 'status': 'success'}),
        );
      } finally {
        _settingUp = false;
      }
      return;
    }
    try {
      result =
          await channel.invokeMapMethod<String, Object?>(action as String, {
            'requestId': id,
            if (action == 'generate') 'prompt': prompt,
            if (action == 'cancel')
              'targetRequestId': message['targetRequestId'],
            if ({'status', 'voice'}.contains(action))
              'locale': message['locale'],
          }) ??
          {'status': 'error', 'code': 'unavailable'};
    } on PlatformException catch (e) {
      result = {'status': 'error', 'code': e.code};
    } on MissingPluginException {
      result = {'status': 'error', 'code': 'unavailable'};
    }
    try {
      onReply?.call(replyWebMessage(data: {...result, 'requestId': id}));
    } catch (_) {
      await channel.invokeMethod('cancel', {'targetRequestId': id});
    }
  }
}
