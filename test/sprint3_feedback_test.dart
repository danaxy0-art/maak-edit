// Sprint 3 test-session feedback: already-reported notice, grey pending
// chips, and centred dialog buttons on the report form.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/design/components.dart';
import 'package:maak_app/frontend/design/tokens.dart';
import 'package:maak_app/frontend/redesign/report_message.dart';
import 'package:maak_app/frontend/redesign/ui.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

Future<void> _openReport(
  WidgetTester tester,
  Future<bool> Function() alreadyReported,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReportMessageDialog(
              context,
              messageId: 'm1',
              alreadyReported: alreadyReported,
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

Color? _background(WidgetTester tester, Finder chip) {
  final box = tester.widget<Container>(
    find.descendant(of: chip, matching: find.byType(Container)).first,
  );
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  group('Report message', () {
    testWidgets('a message already reported shows a notice, not the form', (
      tester,
    ) async {
      await _openReport(tester, () async => true);
      expect(find.text('Already reported'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('already_reported_notice')),
        findsOneWidget,
      );
      expect(find.text('Why are you reporting it?'), findsNothing);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).actionsAlignment,
        MainAxisAlignment.center,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a new message opens the report form, buttons centred', (
      tester,
    ) async {
      await _openReport(tester, () async => false);
      expect(find.text('Why are you reporting it?'), findsOneWidget);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).actionsAlignment,
        MainAxisAlignment.center,
      );
    });

    testWidgets('if the lookup fails, the form still opens', (tester) async {
      await _openReport(tester, () async => throw Exception('offline'));
      expect(find.text('Why are you reporting it?'), findsOneWidget);
    });
  });

  group('Pending chips are grey', () {
    testWidgets('RoleChip pending uses the shared grey; others unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              RoleChip('Pending', key: ValueKey('p'), pending: true),
              RoleChip('Approved', key: ValueKey('n')),
              RoleChip('Rejected', key: ValueKey('e'), error: true),
            ],
          ),
        ),
      );
      expect(
        _background(tester, find.byKey(const ValueKey('p'))),
        MaakColors.pending,
      );
      expect(
        _background(tester, find.byKey(const ValueKey('n'))),
        MaakColors.selected,
      );
      expect(
        _background(tester, find.byKey(const ValueKey('e'))),
        const Color(0xFFFDE8E8),
      );
    });

    test('the grey is neutral and distinct from the old pending colours', () {
      expect(MaakColors.pending, isNot(MaakColors.blush));
      expect(MaakColors.pending, isNot(const Color(0xFFFFE9A8)));
      final c = MaakColors.pending;
      expect(c.r, c.g);
      expect(c.g, c.b);
    });

    testWidgets('StatusPill draws the colour it is given', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StatusPill(
            key: ValueKey('s'),
            label: 'Awaiting response',
            icon: Icons.schedule,
            color: MaakColors.pending,
          ),
        ),
      );
      expect(
        _background(tester, find.byKey(const ValueKey('s'))),
        MaakColors.pending,
      );
    });
  });
}
