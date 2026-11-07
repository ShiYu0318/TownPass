import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:town_pass/util/web_message_handler/codefest_ai_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('codefest/on_device_ai');
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {'status': 'success', 'modelReady': false};
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  final id = 'a' * 32;
  test(
    'approved main-frame status is correlated and never asks permission',
    () async {
      final replies = <WebMessage>[];
      await CodefestAIMessageHandler().handle(
        message: {'requestId': id, 'action': 'status', 'locale': 'zh-TW'},
        sourceOrigin: WebUri('http://127.0.0.1:8082'),
        isMainFrame: true,
        onReply: replies.add,
      );
      expect(calls.single.method, 'status');
      expect(replies, hasLength(1));
      expect(replies.single.data, contains(id));
    },
  );
  test('reject iframe, foreign origin, invalid IDs, locale and oversized prompt before native channel', () async {
    final handler = CodefestAIMessageHandler();
    Future<void> send(
      Map message, {
      String origin = 'http://127.0.0.1:8082',
      bool main = true,
    }) => handler.handle(
      message: message,
      sourceOrigin: WebUri(origin),
      isMainFrame: main,
      onReply: null,
    );
    final status = {'requestId': id, 'action': 'status', 'locale': 'zh-TW'};
    await send(status, main: false);
    await send(status, origin: 'https://evil.example');
    await send(status, origin: 'http://home.yoyo899843.com:8000');
    await send({...status, 'requestId': 'bad'});
    await send({...status, 'locale': 'unsupported'});
    await send({'requestId': id, 'action': 'generate', 'prompt': 'x' * 6001});
    await send({'requestId': id, 'action': 'cancel', 'targetRequestId': 'bad'});
    expect(calls, isEmpty);
  });
}
