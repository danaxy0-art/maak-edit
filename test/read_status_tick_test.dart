// Read status on my own chat messages (F127): one grey tick when sent, two
// green ticks once the other person has seen it (messages.read_at is set).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/design/tokens.dart';
import 'package:maak_app/frontend/redesign/support.dart';

Future<void> _pump(WidgetTester tester, {required bool seen}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: ReadStatusTick(seen: seen))),
      ),
    );

void main() {
  testWidgets('sent: one grey tick, read aloud as "Sent"', (tester) async {
    await _pump(tester, seen: false);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.done);
    expect(icon.color, MaakColors.muted);
    expect(find.bySemanticsLabel('Sent'), findsOneWidget);
  });

  testWidgets('seen: two green ticks, read aloud as "Seen"', (tester) async {
    await _pump(tester, seen: true);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.done_all);
    expect(icon.color, MaakColors.success);
    expect(find.bySemanticsLabel('Seen'), findsOneWidget);
  });
}
