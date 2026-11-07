import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/util/codefest_ai_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native host pop unloads AI independently of JavaScript', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('codefest/on_device_ai'),
          (call) async {
            calls.add(call.method);
            return {'status': 'success'};
          },
        );
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('home')),
      ),
    );
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const CodefestAIScope(
          child: Scaffold(body: Text('web view placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, ['unload']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('codefest/on_device_ai'),
          null,
        );
  });
}
