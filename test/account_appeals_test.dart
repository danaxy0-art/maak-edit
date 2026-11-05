import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/backend/services/supabase_service.dart';
import 'package:maak_app/frontend/auth/blocked_account_screen.dart';
import 'package:maak_app/frontend/redesign/admin.dart';
import 'package:maak_app/frontend/redesign/feedback.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

class _PkceStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

const adminId = '50000000-0000-0000-0000-000000000001';
const memberId = '50000000-0000-0000-0000-000000000002';
const appealId = '50000000-0000-0000-0000-0000000000a1';

Map<String, dynamic> appealStatus({
  int used = 0,
  List<Map<String, dynamic>> appeals = const [],
  String? unavailable,
}) => {
  'blocked': true,
  'block': {'reason': 'Repeated spam', 'blocked_at': '2026-10-18T09:30:00Z'},
  'max_appeals': 3,
  'appeals_used': used,
  'appeals_remaining': 3 - used,
  'can_appeal': unavailable == null,
  'unavailable_reason': unavailable,
  'appeals': appeals,
};

Map<String, dynamic> pendingAppeal({String? blockedBy, bool isMe = false}) => {
  'appeal_id': appealId,
  'user_id': memberId,
  'full_name': 'Huda Ali',
  'username': 'huda',
  'email': 'huda@example.com',
  'role': 'help_seeker',
  'attempt': 2,
  'max_appeals': 3,
  'message': 'I shared the link by mistake. It will not happen again.',
  'submitted_at': '2026-10-20T10:00:00Z',
  'block_reason': 'Repeated spam',
  'blocked_at': '2026-10-18T09:30:00Z',
  'blocked_by_name': blockedBy ?? 'Administrator',
  'blocked_by_is_me': isMe,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  final bodies = <String, Object?>{};
  var overrides = <String, (int, Object?)>{};
  final offline = <String>{};
  final holds = <String, Completer<void>>{};
  // Server state the mock returns.
  var myStatus = appealStatus();
  var pending = <Map<String, dynamic>>[];
  var accountAppeals = <Map<String, dynamic>>[];
  var history = <Map<String, dynamic>>[];
  var blocks = <Map<String, dynamic>>[];

  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      authOptions: FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        pkceAsyncStorage: _PkceStorage(),
      ),
      httpClient: MockClient((request) async {
        final name = request.url.pathSegments.last;
        calls.add(name);
        bodies[name] = request.body.isEmpty ? null : jsonDecode(request.body);
        if (holds[name] != null) await holds[name]!.future;
        if (offline.contains(name)) throw const SocketException('offline');
        Object? data;
        var status = 200;
        if (overrides.containsKey(name)) {
          (status, data) = overrides[name]!;
        } else if (name == 'token') {
          final payload = base64Url
              .encode(
                utf8.encode(jsonEncode({'sub': adminId, 'exp': 4102444800})),
              )
              .replaceAll('=', '');
          data = {
            'access_token': 'e30.$payload.signature',
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': adminId,
              'aud': 'authenticated',
              'email': 'admin@example.com',
              'created_at': '2026-09-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (name == 'my_appeal_status') {
          data = myStatus;
        } else if (name == 'submit_my_appeal') {
          final message = (jsonDecode(request.body) as Map)['p_message'];
          final used = (myStatus['appeals_used'] as int) + 1;
          myStatus = appealStatus(
            used: used,
            unavailable: 'appeal_pending',
            appeals: [
              {
                'attempt': used,
                'status': 'pending',
                'message': message,
                'submitted_at': '2026-10-21T08:00:00Z',
              },
              ...List<Map<String, dynamic>>.from(myStatus['appeals'] as List),
            ],
          );
          data = myStatus;
        } else if (name == 'admin_pending_appeals') {
          data = pending;
        } else if (name == 'admin_account_appeals') {
          data = accountAppeals;
        } else if (name == 'admin_account_moderation_history') {
          data = history;
        } else if (name == 'admin_decide_appeal') {
          final params = jsonDecode(request.body) as Map;
          // Like the database: a decided appeal is no longer pending.
          pending = [
            for (final p in pending)
              if (p['appeal_id'] != params['p_appeal_id']) p,
          ];
          data = {
            'appeal_id': params['p_appeal_id'],
            'status': params['p_approve'] == true ? 'approved' : 'rejected',
            'reactivated': params['p_approve'],
          };
        } else if (name == 'admin_list_accounts') {
          data = [
            {
              'user_id': memberId,
              'full_name': 'Huda Ali',
              'username': 'huda',
              'email': 'huda@example.com',
              'role': 'help_seeker',
              'created_at': '2026-09-10T08:00:00Z',
              'is_blocked': blocks.isNotEmpty,
              'blocked_at': blocks.isEmpty ? null : blocks.first['blocked_at'],
              'can_block': blocks.isEmpty,
            },
          ];
        } else if (name == 'admin_blocked_accounts') {
          data = blocks;
        } else if (name == 'admin_block_account') {
          data = null;
        } else {
          data = [];
        }
        return http.Response(
          jsonEncode(data),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await SupabaseService.signIn(
      email: 'admin@example.com',
      password: 'Test123!',
    );
  });
  setUp(() {
    calls.clear();
    bodies.clear();
    overrides = {};
    offline.clear();
    holds.clear();
    myStatus = appealStatus();
    pending = [];
    accountAppeals = [];
    history = [];
    blocks = [];
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Widget home,
    Size size, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );
    await settle(tester);
  }

  const phone = Size(390, 844);
  const smallPhone = Size(320, 640);
  const tablet = Size(1024, 768);
  const tallPhone = Size(390, 1800);
  const screen = BlockedAccountScreen(
    reason: 'Repeated spam',
    blockedAt: '2026-10-18T09:30:00Z',
  );

  Finder inDialog(Finder f) =>
      find.descendant(of: find.byType(AlertDialog), matching: f);
  Finder confirm(String label) =>
      inDialog(find.widgetWithText(FilledButton, label));
  int count(String name) => calls.where((c) => c == name).length;
  bool enabled(WidgetTester tester, String label) {
    final button = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    if (button.evaluate().isNotEmpty) {
      return tester.widget<ButtonStyleButton>(button.first).onPressed != null;
    }
    // PrimaryButton is a gradient container around an InkWell.
    final ink = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    return tester.widget<InkWell>(ink.first).onTap != null;
  }

  Future<void> openAppealDialog(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Request an appeal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request an appeal'));
    await tester.pumpAndSettle();
  }

  group('Service validation', () {
    test('blank appeal is rejected before any request', () async {
      await expectLater(
        SupabaseService.submitAppeal('   '),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        SupabaseService.submitAppeal('a' * 1001),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isNot(contains('submit_my_appeal')));
    });
    test('appeal text is sent trimmed', () async {
      await SupabaseService.submitAppeal('  Please review  ');
      expect(bodies['submit_my_appeal'], {'p_message': 'Please review'});
    });
    test('rejection requires a note before any request', () async {
      await expectLater(
        SupabaseService.decideAppeal(appealId: appealId, approve: false),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isNot(contains('admin_decide_appeal')));
    });
    test('approval sends no note when blank', () async {
      await SupabaseService.decideAppeal(
        appealId: appealId,
        approve: true,
        note: '  ',
      );
      expect(bodies['admin_decide_appeal'], {
        'p_appeal_id': appealId,
        'p_approve': true,
        'p_note': null,
      });
    });
    test(
      'missing appeals migration is reported as null, not an error',
      () async {
        for (final rpc in ['my_appeal_status', 'admin_pending_appeals']) {
          overrides[rpc] = (
            404,
            {'code': 'PGRST202', 'message': 'Could not find the function'},
          );
        }
        expect(await SupabaseService.getMyAppealStatus(), isNull);
        expect(await SupabaseService.getPendingAppeals(), isNull);
      },
    );
    test('appeal error codes have friendly messages', () {
      String message(String code) =>
          friendlyError(PostgrestException(message: code, code: 'P0001'));
      expect(message('appeal_pending'), contains('already being reviewed'));
      expect(message('appeal_limit_reached'), contains('All 3 appeals'));
      expect(message('account_active'), contains('no longer restricted'));
      expect(message('appeal_already_decided'), contains('already reviewed'));
      expect(message('invalid_appeal_message'), contains('1000'));
      expect(message('invalid_decision_note'), contains('1000'));
      expect(message('appeal_not_found'), contains('no longer exists'));
      expect(message('appeal_not_current'), contains('earlier restriction'));
    });
  });

  group('Blocked-user appeal section', () {
    testWidgets('first appeal is available immediately', (tester) async {
      await pumpAt(tester, screen, phone);
      expect(find.text('Your account has been restricted'), findsOneWidget);
      expect(find.text('Repeated spam'), findsOneWidget);
      expect(find.text('18 Oct 2026'), findsOneWidget);
      expect(
        find.text('3 of 3 appeals remaining for this restriction'),
        findsOneWidget,
      );
      expect(enabled(tester, 'Request an appeal'), isTrue);
      // Check again and Log out stay on screen on a standard phone.
      expect(tester.getRect(find.text('Check again')).bottom, lessThan(844));
      expect(tester.getRect(find.text('Log out')).bottom, lessThan(844));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the old "contact an administrator" sentence is gone', (
      tester,
    ) async {
      await pumpAt(tester, screen, tallPhone);
      expect(
        find.textContaining('If you think this is a mistake'),
        findsNothing,
      );
      expect(
        find.textContaining("contact a Ma'ak administrator"),
        findsNothing,
      );
      expect(find.text('Request an appeal'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets(
      'counter comes from the server each time: a rejection is not restored '
      'and signing out and back in does not reset it',
      (tester) async {
        // Same block, one rejected appeal: the server reports 1 used.
        myStatus = appealStatus(
          used: 1,
          appeals: [
            {
              'attempt': 1,
              'status': 'rejected',
              'submitted_at': '2026-10-20T10:00:00Z',
              'decision_note': 'Not enough detail.',
            },
          ],
        );
        await pumpAt(tester, screen, tallPhone);
        expect(
          find.text('2 of 3 appeals remaining for this restriction'),
          findsOneWidget,
        );
        // Leave the screen (as on sign-out) and come back (sign-in).
        await tester.pumpWidget(const SizedBox());
        await pumpAt(tester, screen, tallPhone);
        expect(
          find.text('2 of 3 appeals remaining for this restriction'),
          findsOneWidget,
        );
        expect(count('my_appeal_status'), 2, reason: 'read fresh each time');
      },
    );

    testWidgets('pending appeal disables the button and says why', (
      tester,
    ) async {
      myStatus = appealStatus(
        used: 1,
        unavailable: 'appeal_pending',
        appeals: [
          {
            'attempt': 1,
            'status': 'pending',
            'submitted_at': '2026-10-20T10:00:00Z',
          },
        ],
      );
      await pumpAt(tester, screen, tallPhone);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Appeal 1 of 3'), findsOneWidget);
      expect(
        find.text('2 of 3 appeals remaining for this restriction'),
        findsOneWidget,
      );
      expect(enabled(tester, 'Request an appeal'), isFalse);
      expect(find.textContaining('being reviewed'), findsOneWidget);
    });

    testWidgets('rejection shows the explanation and the next attempt', (
      tester,
    ) async {
      myStatus = appealStatus(
        used: 1,
        appeals: [
          {
            'attempt': 1,
            'status': 'rejected',
            'submitted_at': '2026-10-20T10:00:00Z',
            'decision_note': 'The messages were confirmed as spam.',
          },
        ],
      );
      await pumpAt(tester, screen, tallPhone);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text("Administrator's response"), findsOneWidget);
      expect(find.text('The messages were confirmed as spam.'), findsOneWidget);
      expect(enabled(tester, 'Request an appeal'), isTrue);
    });

    testWidgets('after three rejections no more appeals are possible', (
      tester,
    ) async {
      myStatus = appealStatus(
        used: 3,
        unavailable: 'appeal_limit_reached',
        appeals: [
          {
            'attempt': 3,
            'status': 'rejected',
            'submitted_at': '2026-10-20T10:00:00Z',
            'decision_note': 'Final decision.',
          },
        ],
      );
      await pumpAt(tester, screen, tallPhone);
      expect(
        find.text('0 of 3 appeals remaining for this restriction'),
        findsOneWidget,
      );
      expect(enabled(tester, 'Request an appeal'), isFalse);
      expect(
        find.text('You have used all 3 appeals for this restriction.'),
        findsOneWidget,
      );
    });

    testWidgets('closed appeals are labelled Closed', (tester) async {
      myStatus = appealStatus(
        used: 1,
        appeals: [
          {
            'attempt': 1,
            'status': 'closed',
            'closed_reason': 'reactivated',
            'submitted_at': '2026-10-20T10:00:00Z',
          },
        ],
      );
      await pumpAt(tester, screen, tallPhone);
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('appeals not installed: section hidden, rest unchanged', (
      tester,
    ) async {
      overrides['my_appeal_status'] = (
        404,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
      );
      await pumpAt(tester, screen, phone);
      expect(find.text('Request an appeal'), findsNothing);
      expect(find.text('Repeated spam'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
    });

    testWidgets('load failure offers a manual Try again', (tester) async {
      offline.add('my_appeal_status');
      await pumpAt(tester, screen, tallPhone);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(count('my_appeal_status'), 1);
      offline.clear();
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(count('my_appeal_status'), 2);
      expect(enabled(tester, 'Request an appeal'), isTrue);
    });

    testWidgets('submission validates inline, then shows Pending', (
      tester,
    ) async {
      await pumpAt(tester, screen, tallPhone);
      await openAppealDialog(tester);
      expect(
        find.textContaining("don't include health details"),
        findsOneWidget,
      );
      await tester.tap(confirm('Submit appeal'));
      await tester.pumpAndSettle();
      expect(
        find.text('Explain why your restriction should be reconsidered'),
        findsOneWidget,
      );
      expect(count('submit_my_appeal'), 0);

      await tester.enterText(
        inDialog(find.byType(TextField)),
        '  It was a misunderstanding.  ',
      );
      await tester.tap(confirm('Submit appeal'));
      await settle(tester);
      expect(bodies['submit_my_appeal'], {
        'p_message': 'It was a misunderstanding.',
      });
      expect(find.text('Appeal submitted.'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(enabled(tester, 'Request an appeal'), isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('double taps while submitting send one request', (
      tester,
    ) async {
      holds['submit_my_appeal'] = Completer<void>();
      await pumpAt(tester, screen, tallPhone);
      await openAppealDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Please');
      await tester.tap(confirm('Submit appeal'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      final busy = confirm('Submitting...');
      expect(tester.widget<FilledButton>(busy).onPressed, isNull);
      await tester.tap(busy, warnIfMissed: false);
      await tester.tap(busy, warnIfMissed: false);
      holds['submit_my_appeal']!.complete();
      await settle(tester);
      expect(count('submit_my_appeal'), 1);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a state change elsewhere closes the dialog and explains', (
      tester,
    ) async {
      overrides['submit_my_appeal'] = (
        400,
        {'code': 'P0001', 'message': 'appeal_pending'},
      );
      await pumpAt(tester, screen, tallPhone);
      await openAppealDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Please');
      await tester.tap(confirm('Submit appeal'));
      await settle(tester);
      expect(find.text('Please check this'), findsOneWidget);
      expect(find.textContaining('already being reviewed'), findsOneWidget);
      expect(count('my_appeal_status'), 2, reason: 'status was reloaded');
    });

    testWidgets('network failure keeps the dialog open for a manual retry', (
      tester,
    ) async {
      offline.add('submit_my_appeal');
      await pumpAt(tester, screen, tallPhone);
      await openAppealDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Please');
      await tester.tap(confirm('Submit appeal'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('dialog stays usable with the keyboard open', (tester) async {
      await pumpAt(tester, screen, phone);
      await openAppealDialog(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final button = confirm('Submit appeal');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(844 - 340));
    });

    for (final entry in {
      'small phone, large text': (smallPhone, 1.5),
      'tablet': (tablet, 1.0),
    }.entries) {
      testWidgets('screen and dialog fit a ${entry.key}', (tester) async {
        final (size, scale) = entry.value;
        await pumpAt(tester, screen, size, textScale: scale);
        expect(tester.takeException(), isNull);
        await openAppealDialog(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Admin appeals', () {
    testWidgets('Accounts shows the pending count and opens Appeals', (
      tester,
    ) async {
      pending = [
        pendingAppeal(),
        {
          ...pendingAppeal(),
          'appeal_id': '50000000-0000-0000-0000-0000000000a2',
          'full_name': 'Omar Saleh',
          'email': 'omar@example.com',
          'username': 'omar',
        },
      ];
      await pumpAt(tester, const AccountsAdminPage(), phone);
      expect(find.text('2 pending appeals'), findsOneWidget);
      expect(find.text('Appeal pending'), findsOneWidget);
      await tester.tap(find.text('Appeals'));
      await settle(tester);
      expect(find.text('2 pending appeals'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'omar@');
      await tester.pumpAndSettle();
      expect(find.text('Omar Saleh'), findsOneWidget);
      expect(find.text('Huda Ali'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching appeals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Appeals card hidden when the migration is not installed', (
      tester,
    ) async {
      overrides['admin_pending_appeals'] = (
        404,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
      );
      await pumpAt(tester, const AccountsAdminPage(), phone);
      expect(find.text('Appeals'), findsNothing);
      expect(find.text('Huda Ali'), findsOneWidget);
    });

    testWidgets('empty, error and pull-to-refresh states', (tester) async {
      await pumpAt(tester, const AppealsAdminPage(), phone);
      expect(find.text('No pending appeals'), findsOneWidget);
      pending = [pendingAppeal()];
      await tester.fling(
        find.text('No pending appeals'),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Huda Ali'), findsOneWidget);
      expect(find.text('1 pending appeal'), findsOneWidget);
    });

    testWidgets('load failure waits for a manual Try again', (tester) async {
      offline.add('admin_pending_appeals');
      await pumpAt(tester, const AppealsAdminPage(), phone);
      expect(find.text('Could not load appeals'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(count('admin_pending_appeals'), 1);
      offline.clear();
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(count('admin_pending_appeals'), 2);
    });

    testWidgets('detail shows appeal, restriction, earlier appeals, history', (
      tester,
    ) async {
      accountAppeals = [
        {
          'appeal_id': appealId,
          'is_current_block': true,
          'attempt': 2,
          'status': 'pending',
        },
        {
          'appeal_id': 'earlier',
          'is_current_block': true,
          'attempt': 1,
          'status': 'rejected',
          'message': 'First explanation.',
          'decision_note': 'Not enough detail.',
          'submitted_at': '2026-10-19T10:00:00Z',
          'decided_by_name': 'Administrator',
          'decided_by_is_me': false,
        },
        {
          'appeal_id': 'old-block',
          'is_current_block': false,
          'attempt': 1,
          'status': 'closed',
          'message': 'Old block appeal.',
        },
      ];
      history = [
        {
          'action': 'appeal_rejected',
          'attempt': 1,
          'reason': 'Not enough detail.',
          'actor_name': 'Administrator',
          'actor_is_me': false,
          'created_at': '2026-10-19T12:00:00Z',
        },
        {
          'action': 'appeal_closed',
          'attempt': 1,
          'closed_reason': 'reactivated',
          'actor_name': 'Admin Two',
          'actor_is_me': false,
          'created_at': '2026-09-19T12:00:00Z',
        },
        {
          'action': 'appeal_submitted',
          'attempt': 1,
          'redacted': true,
          'created_at': '2026-09-18T12:00:00Z',
        },
      ];
      await pumpAt(
        tester,
        AppealDetailPage(appeal: pendingAppeal(blockedBy: 'Sara', isMe: true)),
        tallPhone,
      );
      expect(
        find.text('I shared the link by mistake. It will not happen again.'),
        findsOneWidget,
      );
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Repeated spam'), findsOneWidget);
      expect(find.text('Sara (you)'), findsOneWidget);
      expect(find.text('First explanation.'), findsOneWidget);
      expect(find.text('Response: Not enough detail.'), findsOneWidget);
      expect(find.text('Old block appeal.'), findsNothing);
      expect(find.text('Appeal 1 rejected'), findsOneWidget);
      expect(
        find.text('Closed because the account was reactivated.'),
        findsOneWidget,
      );
      expect(
        find.text('Explanation removed when the account was deleted.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('reject requires a reason inline, then rejects', (
      tester,
    ) async {
      await pumpAt(
        tester,
        AppealDetailPage(appeal: pendingAppeal()),
        tallPhone,
      );
      await tester.tap(find.text('Reject appeal'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Huda Ali')), findsOneWidget);
      await tester.tap(confirm('Reject appeal'));
      await tester.pumpAndSettle();
      expect(find.text('Explain why the appeal is rejected'), findsWidgets);
      expect(count('admin_decide_appeal'), 0);
      await tester.enterText(
        inDialog(find.byType(TextField)),
        ' Evidence confirms it. ',
      );
      await tester.tap(confirm('Reject appeal'));
      await settle(tester);
      expect(bodies['admin_decide_appeal'], {
        'p_appeal_id': appealId,
        'p_approve': false,
        'p_note': 'Evidence confirms it.',
      });
      expect(find.text('Appeal rejected.'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Approve appeal'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'approving returns to the refreshed pending list without that appeal',
      (tester) async {
        pending = [
          pendingAppeal(),
          {
            ...pendingAppeal(),
            'appeal_id': '50000000-0000-0000-0000-0000000000a2',
            'user_id': '50000000-0000-0000-0000-000000000003',
            'full_name': 'Omar Saleh',
            'email': 'omar@example.com',
          },
        ];
        await pumpAt(tester, const AppealsAdminPage(), tallPhone);
        expect(find.text('2 pending appeals'), findsOneWidget);
        await tester.tap(find.text('Huda Ali'));
        await settle(tester);
        expect(find.text('Appeal details'), findsOneWidget);

        await tester.tap(find.text('Approve appeal'));
        await tester.pumpAndSettle();
        await tester.tap(confirm('Approve appeal'));
        await settle(tester);

        expect(bodies['admin_decide_appeal'], {
          'p_appeal_id': appealId,
          'p_approve': true,
          'p_note': null,
        });
        expect(
          find.text('Appeal approved. Account reactivated.'),
          findsOneWidget,
        );
        // Back on the list, reloaded: the approved appeal is gone.
        expect(find.text('Appeal details'), findsNothing);
        expect(find.text('Appeals'), findsOneWidget);
        expect(count('admin_pending_appeals'), 2);
        expect(find.text('1 pending appeal'), findsOneWidget);
        expect(find.text('Huda Ali'), findsNothing);
        expect(find.text('Omar Saleh'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'earlier appeals are matched by blocking event, also after the block ended',
      (tester) async {
        // As admin_account_appeals() returns them once the block is gone:
        // is_current_block is false for every appeal of that restriction.
        accountAppeals = [
          {
            'appeal_id': appealId,
            'block_event_id': 'block-2',
            'is_current_block': false,
            'attempt': 2,
            'status': 'pending',
          },
          {
            'appeal_id': 'same-block',
            'block_event_id': 'block-2',
            'is_current_block': false,
            'attempt': 1,
            'status': 'rejected',
            'message': 'My first explanation.',
            'decision_note': 'Not enough detail.',
            'submitted_at': '2026-10-19T10:00:00Z',
          },
          {
            'appeal_id': 'older-block',
            'block_event_id': 'block-1',
            'is_current_block': false,
            'attempt': 1,
            'status': 'approved',
            'message': 'Appeal from an earlier restriction.',
          },
        ];
        await pumpAt(
          tester,
          AppealDetailPage(appeal: pendingAppeal()),
          tallPhone,
        );
        expect(
          find.text('This is the first appeal for this restriction.'),
          findsNothing,
        );
        expect(find.text('My first explanation.'), findsOneWidget);
        expect(find.text('Appeal from an earlier restriction.'), findsNothing);
      },
    );

    testWidgets(
      'an approved appeal stays in the member\'s account history afterwards',
      (tester) async {
        history = [
          {
            'action': 'reactivated',
            'reason': 'Appeal approved',
            'actor_name': 'Administrator',
            'actor_is_me': true,
            'created_at': '2026-10-21T09:00:00Z',
          },
          {
            'action': 'appeal_approved',
            'attempt': 2,
            'actor_name': 'Administrator',
            'actor_is_me': true,
            'created_at': '2026-10-21T09:00:00Z',
          },
          {
            'action': 'appeal_submitted',
            'attempt': 2,
            'reason': 'I shared the link by mistake.',
            'created_at': '2026-10-20T10:00:00Z',
          },
        ];
        await pumpAt(
          tester,
          AccountDetailPage(
            account: {
              'user_id': memberId,
              'full_name': 'Huda Ali',
              'username': 'huda',
              'created_at': '2026-09-10T08:00:00Z',
              'email': 'huda@example.com',
              'role': 'help_seeker',
              'is_blocked': false,
            },
          ),
          tallPhone,
        );
        expect(find.text('Appeal 2 approved'), findsOneWidget);
        expect(find.text('Appeal 2 submitted'), findsOneWidget);
        expect(find.text('I shared the link by mistake.'), findsOneWidget);
        expect(find.text('Reactivated'), findsOneWidget);
        expect(find.text('Block account'), findsOneWidget);
      },
    );

    testWidgets('an appeal already decided by another admin is explained', (
      tester,
    ) async {
      overrides['admin_decide_appeal'] = (
        400,
        {'code': 'P0001', 'message': 'appeal_already_decided'},
      );
      await pumpAt(
        tester,
        AppealDetailPage(appeal: pendingAppeal()),
        tallPhone,
      );
      await tester.tap(find.text('Approve appeal'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('Approve appeal'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('Another administrator has already reviewed'),
        findsOneWidget,
      );
    });

    testWidgets('a refresh detects a decision made elsewhere', (tester) async {
      accountAppeals = [
        {
          'appeal_id': appealId,
          'is_current_block': false,
          'attempt': 2,
          'status': 'approved',
        },
      ];
      await pumpAt(
        tester,
        AppealDetailPage(appeal: pendingAppeal()),
        tallPhone,
      );
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Approve appeal'), findsNothing);
      expect(
        find.textContaining('Another administrator has already reviewed'),
        findsOneWidget,
      );
    });

    testWidgets('double taps on a decision send one request', (tester) async {
      holds['admin_decide_appeal'] = Completer<void>();
      await pumpAt(
        tester,
        AppealDetailPage(appeal: pendingAppeal()),
        tallPhone,
      );
      await tester.tap(find.text('Approve appeal'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('Approve appeal'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      final busy = confirm('Approving...');
      expect(tester.widget<FilledButton>(busy).onPressed, isNull);
      await tester.tap(busy, warnIfMissed: false);
      holds['admin_decide_appeal']!.complete();
      await settle(tester);
      expect(count('admin_decide_appeal'), 1);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('tablet places the appeal and restriction side by side', (
      tester,
    ) async {
      await pumpAt(tester, AppealDetailPage(appeal: pendingAppeal()), tablet);
      final appeal = tester.getTopLeft(find.text('Appeal'));
      final restriction = tester.getTopLeft(find.text('Original restriction'));
      expect(appeal.dy, restriction.dy);
      expect(restriction.dx, greaterThan(appeal.dx));
      expect(tester.takeException(), isNull);
    });
  });

  group('Blocked by label (verified by the server)', () {
    Map<String, dynamic> block(String name, bool isMe) => {
      'user_id': memberId,
      'reason': 'Repeated spam',
      'blocked_at': '2026-10-18T09:30:00Z',
      'blocked_by_name': name,
      'blocked_by_is_me': isMe,
      'times_blocked': 1,
    };
    // Complete optional fields, so any "Not provided" could only come from
    // the "Blocked by" row.
    Map<String, dynamic> account(Map<String, dynamic> b) => {
      'user_id': memberId,
      'full_name': 'Huda Ali',
      'username': 'huda',
      'created_at': '2026-09-10T08:00:00Z',
      'email': 'huda@example.com',
      'role': 'help_seeker',
      'is_blocked': true,
      'block': b,
    };

    for (final entry in {
      'unnamed admin': (block('Administrator', false), 'Administrator'),
      'named admin': (block('Sara Bawazeer', false), 'Sara Bawazeer'),
      'deleted admin': (
        block('Former administrator', false),
        'Former administrator',
      ),
      'the signed-in admin': (
        block('Sara Bawazeer', true),
        'Sara Bawazeer (you)',
      ),
    }.entries) {
      testWidgets('shows "${entry.value.$2}" for ${entry.key}', (tester) async {
        blocks = [entry.value.$1];
        await pumpAt(
          tester,
          AccountDetailPage(account: account(entry.value.$1)),
          tallPhone,
        );
        expect(find.text(entry.value.$2), findsOneWidget);
        expect(find.text('Not provided'), findsNothing);
      });
    }

    testWidgets('multiple admins: "(you)" only for the blocker', (
      tester,
    ) async {
      blocks = [block('Admin Two', false)];
      await pumpAt(
        tester,
        AccountDetailPage(account: account(block('Admin Two', false))),
        tallPhone,
      );
      expect(find.text('Admin Two'), findsOneWidget);
      expect(find.textContaining('(you)'), findsNothing);
    });

    testWidgets('after blocking: "Updating details…", then the stored label', (
      tester,
    ) async {
      await pumpAt(
        tester,
        AccountDetailPage(
          account: {
            'user_id': memberId,
            'full_name': 'Huda Ali',
            'email': 'huda@example.com',
            'role': 'help_seeker',
            'is_blocked': false,
          },
        ),
        tallPhone,
      );
      await tester.tap(find.text('Block account'));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Spam');
      holds['admin_list_accounts'] = Completer<void>();
      blocks = [block('Administrator', true)];
      await tester.tap(confirm('Block account'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Updating details…'), findsWidgets);
      expect(find.text('You'), findsNothing);
      holds['admin_list_accounts']!.complete();
      await settle(tester);
      expect(find.text('Updating details…'), findsNothing);
      expect(find.text('Administrator (you)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('pending appeal banner opens the appeal', (tester) async {
      blocks = [block('Administrator', false)];
      await pumpAt(
        tester,
        AccountDetailPage(
          account: {
            ...account(block('Administrator', false)),
            'pending_appeal': pendingAppeal(),
          },
        ),
        tallPhone,
      );
      expect(find.text('Pending appeal · attempt 2 of 3'), findsOneWidget);
      await tester.tap(find.text('Review appeal'));
      await settle(tester);
      expect(find.text('Appeal details'), findsOneWidget);
    });
  });
}
