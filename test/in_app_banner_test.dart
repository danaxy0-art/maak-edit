// ADDED: checks for the pop-up banner (uses the `stream` test hook, no Supabase).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/redesign/in_app_banner.dart';

Map<String, dynamic> _n(String id, {bool read = false, String kind = 'request'}) => {
  'id': id,
  'title': 'Title $id',
  'body': 'Body $id',
  'kind': kind,
  'is_read': read,
};

void main() {
  late StreamController<List<Map<String, dynamic>>> controller;
  late List<Map<String, dynamic>> opened;

  Future<void> pumpHost(WidgetTester tester, {Duration? visibleFor}) async {
    controller = StreamController<List<Map<String, dynamic>>>();
    opened = [];
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBannerHost(
            stream: controller.stream,
            visibleFor: visibleFor ?? const Duration(seconds: 5),
            onOpen: opened.add,
            child: const Center(child: Text('page')),
          ),
        ),
      ),
    );
  }

  testWidgets('BAN-01 existing notifications do not pop up', (tester) async {
    await pumpHost(tester);
    controller.add([_n('1'), _n('2')]);
    await tester.pump();
    expect(find.text('Title 1'), findsNothing);
  });

  testWidgets('BAN-02 a new unread notification pops up', (tester) async {
    await pumpHost(tester);
    controller.add([_n('1')]);
    await tester.pump();
    controller.add([_n('2'), _n('1')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Title 2'), findsOneWidget);
    expect(find.text('Body 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('BAN-03 an already-read new row does not pop up', (tester) async {
    await pumpHost(tester);
    controller.add([_n('1')]);
    await tester.pump();
    controller.add([_n('2', read: true), _n('1')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Title 2'), findsNothing);
  });

  testWidgets('BAN-04 the banner disappears by itself', (tester) async {
    await pumpHost(tester, visibleFor: const Duration(seconds: 2));
    controller.add([_n('1')]);
    await tester.pump();
    controller.add([_n('2'), _n('1')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Title 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Title 2'), findsNothing);
  });

  testWidgets('BAN-05 tapping the banner opens that notification', (
    tester,
  ) async {
    await pumpHost(tester);
    controller.add([_n('1')]);
    await tester.pump();
    controller.add([_n('2'), _n('1')]);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Title 2'));
    await tester.pumpAndSettle();
    expect(opened.single['id'], '2');
    expect(find.text('Title 2'), findsNothing);
  });

  testWidgets('BAN-06 the close button dismisses without opening', (
    tester,
  ) async {
    await pumpHost(tester);
    controller.add([_n('1')]);
    await tester.pump();
    controller.add([_n('2'), _n('1')]);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('banner_close')));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('Title 2'), findsNothing);
  });

  testWidgets('BAN-07 several at once shows the newest with a count', (
    tester,
  ) async {
    await pumpHost(tester);
    controller.add([_n('1')]);
    await tester.pump();
    controller.add([_n('4'), _n('3'), _n('2'), _n('1')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Title 4'), findsOneWidget);
    expect(find.textContaining('+2 more'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('BAN-08 disabled host never pops up (Help Seeker)', (tester) async {
    controller = StreamController<List<Map<String, dynamic>>>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBannerHost(
            enabled: false,
            stream: controller.stream,
            onOpen: (_) {},
            child: const Center(child: Text('page')),
          ),
        ),
      ),
    );
    controller.add([_n('1')]);
    await tester.pump();
    controller.add([_n('2'), _n('1')]);
    await tester.pump();
    expect(find.text('page'), findsOneWidget);
    expect(find.text('Title 2'), findsNothing);
  });
}
