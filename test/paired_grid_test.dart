// PairedGrid (wide layouts such as My journey and the volunteer directory):
// cards go two per row, and a lone last card is centred at the same width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/design/components.dart';

void main() {
  Future<void> pump(WidgetTester tester, int count) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            child: PairedGrid(
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(key: ValueKey('card$i'), height: 100),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Rect card(WidgetTester tester, int i) =>
      tester.getRect(find.byKey(ValueKey('card$i')));

  testWidgets('a single card is centred at half width', (tester) async {
    await pump(tester, 1);
    final grid = tester.getRect(find.byType(PairedGrid));
    final only = card(tester, 0);
    expect(only.center.dx, moreOrLessEquals(grid.center.dx));
    expect(only.width, lessThan(grid.width / 2));
  });

  testWidgets('pairs fill the row and an odd last card is centred', (
    tester,
  ) async {
    await pump(tester, 3);
    final grid = tester.getRect(find.byType(PairedGrid));
    expect(card(tester, 0).left, moreOrLessEquals(grid.left));
    expect(card(tester, 1).right, moreOrLessEquals(grid.right));
    expect(card(tester, 0).width, moreOrLessEquals(card(tester, 1).width));
    final last = card(tester, 2);
    expect(last.width, moreOrLessEquals(card(tester, 0).width));
    expect(last.center.dx, moreOrLessEquals(grid.center.dx));
    expect(last.top, greaterThan(card(tester, 0).bottom));
  });
}
