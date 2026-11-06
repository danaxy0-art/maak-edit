// ADDED: widget checks for the report dialog (uses the `submit` test hook, no Supabase).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/redesign/report_message.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(String, String?) submit,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) =>
                  ReportMessageDialog(messageId: 'm1', submit: submit),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('RPT-UI-01 shows the five reasons', (tester) async {
    await _open(tester, (_, __) async {});
    for (final r in kReportReasons) {
      expect(find.text(r.$2), findsOneWidget);
    }
  });

  testWidgets('RPT-UI-02 cannot send without a reason', (tester) async {
    var calls = 0;
    await _open(tester, (_, __) async => calls++);
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reason_error')), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('RPT-UI-03 sends the chosen reason without a description', (
    tester,
  ) async {
    String? reason, description = 'unset';
    await _open(tester, (r, d) async {
      reason = r;
      description = d;
    });
    await tester.tap(find.byKey(const ValueKey('reason_spam')));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(reason, 'spam');
    expect(description, isNull);
  });

  testWidgets('RPT-UI-04 sends the optional description', (tester) async {
    String? description;
    await _open(tester, (_, d) async => description = d);
    await tester.tap(find.byKey(const ValueKey('reason_harassment')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  Rude to me  ');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(description, 'Rude to me');
  });
}
