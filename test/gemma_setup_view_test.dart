import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/page/codefest_ai/gemma_setup_view.dart';

void main() {
  testWidgets(
    'one-tap setup has no account token field and unpublished release cannot download',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GemmaSetupView()));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('下載一次，之後離線使用'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNull,
      );
    },
  );
}
