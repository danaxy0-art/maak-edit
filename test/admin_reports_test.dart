// Admin report management UI (US1-US5). Supabase is replaced by a mock HTTP
// client; no network or database is used. Server rules are covered by
// tests/database/admin_reports_test.mjs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/backend/services/supabase_service.dart';
import 'package:maak_app/backend/validation/form_policy.dart';
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

const adminId = '60000000-0000-0000-0000-000000000001';
const r1 = '60000000-0000-0000-0000-0000000000a1';
const r2 = '60000000-0000-0000-0000-0000000000a2';
const r3 = '60000000-0000-0000-0000-0000000000a3';

Map<String, dynamic> member(String name, String role, {bool blocked = false}) =>
    {
      'user_id': '60000000-0000-0000-0000-00000000${name.length}00',
      'account_exists': true,
      'name': name,
      'role': role,
      'is_blocked': blocked,
    };

Map<String, dynamic> reportRow(
  String id, {
  String status = 'open',
  String reason = 'harassment',
  String preview = 'You are useless',
  int openInConversation = 1,
  String? decidedBy,
  String? note,
}) => {
  'report_id': id,
  'status': status,
  'reason': reason,
  'description': 'He keeps insulting me',
  'created_at': '2026-11-05T10:00:00Z',
  'request_id': '60000000-0000-0000-0000-0000000000c1',
  'message_id': '60000000-0000-0000-0000-0000000000d1',
  'message_type': 'text',
  'message_preview': preview,
  'message_sent_at': '2026-11-05T09:58:00Z',
  'reporter': member('Sara Seeker', 'help_seeker'),
  'reported': member('Vera Volunteer', 'volunteer'),
  'decided_at': decidedBy == null ? null : '2026-11-06T08:00:00Z',
  'decision_note': note,
  'decided_by_name': decidedBy,
  'decided_by_is_me': decidedBy == 'Amal Admin',
  'conversation_open_reports': openInConversation,
  'conversation_restricted': status == 'conversation_ended',
};

Map<String, dynamic> details(
  Map<String, dynamic> row, {
  bool deleted = false,
  bool restricted = false,
  bool conversationExists = true,
  List<Map<String, dynamic>>? others,
}) => {
  ...row,
  'message_body': row['message_preview'],
  'attachment_present': false,
  'message_now': {'exists': true, 'deleted': deleted, 'deleted_at': null},
  'conversation': {
    'exists': conversationExists,
    'status': 'accepted',
    'created_at': '2026-10-30T10:00:00Z',
    'ended_at': null,
    'restricted_at': restricted ? '2026-11-06T08:00:00Z' : null,
    'restriction_reason': restricted ? 'Harassment' : null,
    'restricted_by_name': restricted ? 'Basma Admin' : null,
    'restricted_by_is_me': false,
    'help_seeker': member('Sara Seeker', 'help_seeker'),
    'volunteer': member('Vera Volunteer', 'volunteer'),
  },
  'context': conversationExists
      ? [
          {
            'message_id': 'm0',
            'body': 'How was your week?',
            'message_type': 'text',
            'created_at': '2026-11-05T09:50:00Z',
            'deleted': false,
            'is_reported': false,
            'sender': 'reporter',
          },
          {
            'message_id': 'm1',
            'body': deleted
                ? 'This message was deleted.'
                : row['message_preview'],
            'message_type': 'text',
            'created_at': '2026-11-05T09:58:00Z',
            'deleted': deleted,
            'is_reported': true,
            'sender': 'reported',
          },
        ]
      : [],
  'other_reports': others ?? [],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  final bodies = <String, Object?>{};
  var overrides = <String, (int, Object?)>{};
  final offline = <String>{};
  final holds = <String, Completer<void>>{};
  var reports = <Map<String, dynamic>>[];
  var detail = <String, Map<String, dynamic>>{};

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
        final params = request.body.isEmpty
            ? null
            : jsonDecode(request.body) as Map?;
        bodies[name] = params;
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
        } else if (name == 'admin_list_reports') {
          data = reports;
        } else if (name == 'admin_report_details') {
          data = detail[params!['p_report_id']];
        } else if (name == 'admin_dismiss_report' ||
            name == 'admin_end_reported_conversation') {
          final id = params!['p_report_id'] as String;
          final ended = name == 'admin_end_reported_conversation';
          final note = (params['p_note'] ?? params['p_reason']) as String;
          // Like the database: the report is decided once.
          final updated = {
            ...detail[id]!,
            'status': ended ? 'conversation_ended' : 'dismissed',
            'decided_at': '2026-11-06T09:00:00Z',
            'decided_by_name': 'Amal Admin',
            'decided_by_is_me': true,
            'decision_note': note,
          };
          detail[id] = updated;
          reports = [
            for (final r in reports)
              if (r['report_id'] == id)
                {...r, 'status': updated['status']}
              else
                r,
          ];
          data = ended
              ? {
                  'report_id': id,
                  'status': 'conversation_ended',
                  'resolved_reports': 2,
                }
              : {'report_id': id, 'status': 'dismissed'};
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
    reports = [];
    detail = {};
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

  Future<void> pumpAt(WidgetTester tester, Widget home, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
    await settle(tester);
  }

  const phone = Size(390, 844);
  const tallPhone = Size(390, 2600);
  const smallPhone = Size(320, 640);
  const tablet = Size(1024, 1400);
  int count(String name) => calls.where((c) => c == name).length;
  Finder inDialog(Finder f) =>
      find.descendant(of: find.byType(AlertDialog), matching: f);
  Finder confirm(String label) =>
      inDialog(find.widgetWithText(FilledButton, label));
  void seed() {
    reports = [
      reportRow(r1, openInConversation: 2),
      reportRow(
        r2,
        status: 'dismissed',
        reason: 'spam',
        preview: 'Buy now',
        decidedBy: 'Basma Admin',
        note: 'Not spam',
      ),
      reportRow(
        r3,
        status: 'conversation_ended',
        reason: 'unwanted_medical_advice',
        preview: 'Stop your insulin',
        decidedBy: 'Amal Admin',
        note: 'Dangerous advice',
      ),
    ];
    for (final r in reports) {
      detail[r['report_id'] as String] = details(
        r,
        restricted: r['status'] == 'conversation_ended',
      );
    }
  }

  Future<void> openDetail(
    WidgetTester tester,
    String id, {
    Size size = tallPhone,
  }) async {
    final row = reports.firstWhere((r) => r['report_id'] == id);
    await pumpAt(tester, ReportDetailPage(report: row), size);
  }

  group('US1 reports list', () {
    testWidgets('Overview links to Message reports', (tester) async {
      seed();
      await pumpAt(tester, AdminOverview(select: (_) {}), tallPhone);
      await tester.tap(find.text('Message reports'));
      await settle(tester);
      expect(find.text('1 report needs review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading spinner, then open reports by default', (
      tester,
    ) async {
      seed();
      holds['admin_list_reports'] = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const ReportsAdminPage()),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      holds['admin_list_reports']!.complete();
      await settle(tester);
      expect(find.text('Harassment'), findsOneWidget);
      expect(find.text('Spam'), findsNothing);
      expect(find.text('"You are useless"'), findsOneWidget);
      expect(
        find.text('Reported member: Vera Volunteer · Volunteer'),
        findsOneWidget,
      );
      expect(find.text('2 open reports in this conversation'), findsOneWidget);
      expect(find.text('Open (1)'), findsOneWidget);
      expect(find.text('Dismissed (1)'), findsOneWidget);
      expect(find.text('Conversation ended (1)'), findsOneWidget);
      expect(find.text('All (3)'), findsOneWidget);
    });

    testWidgets('status filters show matching reports and their status', (
      tester,
    ) async {
      seed();
      await pumpAt(tester, const ReportsAdminPage(), phone);
      await tester.tap(find.byKey(const ValueKey('report_filter_dismissed')));
      await tester.pumpAndSettle();
      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('Harassment'), findsNothing);
      expect(find.text('Dismissed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report_filter_ended')));
      await tester.pumpAndSettle();
      expect(find.text('Unwanted medical advice'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report_filter_all')));
      await tester.pumpAndSettle();
      expect(find.text('Harassment'), findsOneWidget);
      expect(find.text('Spam'), findsOneWidget);
      expect(count('admin_list_reports'), 1, reason: 'filters are local');
    });

    testWidgets('empty states: none at all, and none in a filter', (
      tester,
    ) async {
      await pumpAt(tester, const ReportsAdminPage(), phone);
      expect(find.text('No reports yet'), findsOneWidget);
      reports = [reportRow(r2, status: 'dismissed', decidedBy: 'Basma Admin')];
      await tester.fling(
        find.text('No reports yet'),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('No open reports'), findsOneWidget);
      expect(find.text('Nothing needs review right now.'), findsOneWidget);
    });

    testWidgets('migration not installed is explained', (tester) async {
      overrides['admin_list_reports'] = (
        404,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
      );
      await pumpAt(tester, const ReportsAdminPage(), phone);
      expect(find.text('Reports are not available yet'), findsOneWidget);
    });

    testWidgets('load failure waits for a manual Try again', (tester) async {
      offline.add('admin_list_reports');
      await pumpAt(tester, const ReportsAdminPage(), phone);
      expect(find.text('Could not load reports'), findsOneWidget);
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
      offline.clear();
      seed();
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Harassment'), findsOneWidget);
      expect(count('admin_list_reports'), 2);
    });

    testWidgets('a non-admin session gets the permission message', (
      tester,
    ) async {
      overrides['admin_list_reports'] = (
        400,
        {'code': 'P0001', 'message': 'not_allowed'},
      );
      await pumpAt(tester, const ReportsAdminPage(), phone);
      expect(
        find.text('Sign in with an account permitted to perform this action.'),
        findsOneWidget,
      );
    });

    testWidgets('fits a small phone without overflow', (tester) async {
      seed();
      await pumpAt(tester, const ReportsAdminPage(), smallPhone);
      expect(tester.takeException(), isNull);
    });
  });

  group('US2 report details', () {
    testWidgets('shows reason, description, evidence, context and people', (
      tester,
    ) async {
      seed();
      detail[r1] = details(
        reports.first,
        others: [
          {
            'report_id': 'x',
            'reason': 'spam',
            'status': 'open',
            'created_at': '2026-11-05T11:00:00Z',
            'same_message': false,
            'reporter_name': 'Vera Volunteer',
          },
        ],
      );
      await openDetail(tester, r1);
      expect(find.text('He keeps insulting me'), findsOneWidget);
      expect(find.byKey(const ValueKey('report_evidence')), findsOneWidget);
      expect(find.text('Reported message'), findsWidgets);
      expect(find.text('How was your week?'), findsOneWidget);
      expect(find.text('Reported by'), findsOneWidget);
      expect(find.text('Other reports in this conversation'), findsOneWidget);
      expect(
        find.text('Waiting for an administrator decision'),
        findsOneWidget,
      );
      expect(find.text('Dismiss report'), findsOneWidget);
      expect(find.text('End conversation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a deleted message keeps the saved copy and says so', (
      tester,
    ) async {
      seed();
      detail[r1] = details(reports.first, deleted: true);
      await openDetail(tester, r1);
      expect(find.text('This message was deleted.'), findsOneWidget);
      expect(
        find.textContaining('The sender deleted this message after it was'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('report_evidence')), findsOneWidget);
    });

    testWidgets('a decided report shows its decision and no actions', (
      tester,
    ) async {
      seed();
      await openDetail(tester, r3);
      expect(
        find.text('Conversation ended by Amal Admin (you)'),
        findsOneWidget,
      );
      expect(find.text('Dangerous advice'), findsOneWidget);
      expect(find.text('Ended by an administrator'), findsOneWidget);
      expect(find.text('Dismiss report'), findsNothing);
    });

    testWidgets('load error offers Try again', (tester) async {
      seed();
      offline.add('admin_report_details');
      await openDetail(tester, r1);
      expect(find.text('Could not load this report'), findsOneWidget);
      offline.clear();
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('He keeps insulting me'), findsOneWidget);
    });

    testWidgets('a decision made elsewhere since the list loaded is shown', (
      tester,
    ) async {
      seed();
      detail[r1] = {
        ...detail[r1]!,
        'status': 'dismissed',
        'decided_at': '2026-11-06T08:00:00Z',
        'decided_by_name': 'Basma Admin',
        'decided_by_is_me': false,
        'decision_note': 'Handled',
      };
      await openDetail(tester, r1);
      expect(
        find.textContaining('Another administrator has already decided'),
        findsOneWidget,
      );
      expect(find.text('Dismissed by Basma Admin'), findsOneWidget);
      expect(find.text('Dismiss report'), findsNothing);
    });

    testWidgets('tablet places report and people side by side', (tester) async {
      seed();
      await openDetail(tester, r1, size: tablet);
      final report = tester.getTopLeft(find.text('Report'));
      final people = tester.getTopLeft(find.text('People'));
      expect(report.dy, people.dy);
      expect(people.dx, greaterThan(report.dx));
      expect(tester.takeException(), isNull);
    });
  });

  group('US3 dismiss and US5 history', () {
    testWidgets('dismiss requires a reason, then records the decision', (
      tester,
    ) async {
      seed();
      await openDetail(tester, r1);
      await tester.tap(find.text('Dismiss report'));
      await tester.pumpAndSettle();
      expect(find.text('Dismiss this report?'), findsOneWidget);
      expect(find.textContaining('Only administrators see'), findsOneWidget);
      await tester.tap(confirm('Dismiss report'));
      await tester.pumpAndSettle();
      expect(find.text('Explain why this report is dismissed'), findsOneWidget);
      expect(count('admin_dismiss_report'), 0);
      await tester.enterText(
        inDialog(find.byType(TextField)),
        ' No rule broken ',
      );
      await tester.tap(confirm('Dismiss report'));
      await settle(tester);
      expect(count('admin_dismiss_report'), 1);
      expect(bodies['admin_dismiss_report'], {
        'p_report_id': r1,
        'p_note': 'No rule broken',
      });
      expect(
        find.text('Report dismissed. The conversation is not affected.'),
        findsOneWidget,
      );
      expect(find.text('Dismissed by Amal Admin (you)'), findsOneWidget);
      expect(find.text('No rule broken'), findsOneWidget);
      expect(find.text('End conversation'), findsNothing);
    });

    testWidgets('cancel sends nothing', (tester) async {
      seed();
      await openDetail(tester, r1);
      await tester.tap(find.text('Dismiss report'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(count('admin_dismiss_report'), 0);
      expect(find.text('Dismiss report'), findsOneWidget);
    });

    testWidgets('double taps send one decision', (tester) async {
      seed();
      await openDetail(tester, r1);
      await tester.tap(find.text('Dismiss report'));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Fine');
      holds['admin_dismiss_report'] = Completer<void>();
      await tester.tap(confirm('Dismiss report'));
      await tester.pump();
      expect(find.text('Dismissing...'), findsOneWidget);
      await tester.tap(
        inDialog(find.text('Dismissing...')),
        warnIfMissed: false,
      );
      await tester.pump();
      holds['admin_dismiss_report']!.complete();
      await settle(tester);
      expect(count('admin_dismiss_report'), 1);
    });

    testWidgets('another admin deciding first closes the dialog and explains', (
      tester,
    ) async {
      seed();
      await openDetail(tester, r1);
      overrides['admin_dismiss_report'] = (
        400,
        {'code': 'P0001', 'message': 'report_already_decided'},
      );
      await tester.tap(find.text('Dismiss report'));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Fine');
      await tester.tap(confirm('Dismiss report'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('changed elsewhere. The latest status is shown.'),
        findsOneWidget,
      );
      expect(count('admin_report_details'), 2);
    });

    testWidgets('a network failure keeps the dialog open for a retry', (
      tester,
    ) async {
      seed();
      await openDetail(tester, r1);
      await tester.tap(find.text('Dismiss report'));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Fine');
      offline.add('admin_dismiss_report');
      await tester.tap(confirm('Dismiss report'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        inDialog(find.text('Check your internet connection and try again.')),
        findsOneWidget,
      );
    });
  });

  group('US4 end conversation', () {
    testWidgets('confirmation explains the effect, then ends the chat', (
      tester,
    ) async {
      seed();
      await openDetail(tester, r1);
      await tester.tap(find.text('End conversation'));
      await tester.pumpAndSettle();
      expect(find.text('End this conversation?'), findsOneWidget);
      expect(find.textContaining('no account is blocked'), findsOneWidget);
      expect(
        find.textContaining('All 2 open reports on this conversation'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Reason shown to both participants',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tap(confirm('End conversation'));
      await tester.pumpAndSettle();
      expect(
        find.text('Explain why this conversation is ended'),
        findsOneWidget,
      );
      await tester.enterText(
        inDialog(find.byType(TextField)),
        'Repeated harassment',
      );
      await tester.tap(confirm('End conversation'));
      await settle(tester);
      expect(bodies['admin_end_reported_conversation'], {
        'p_report_id': r1,
        'p_reason': 'Repeated harassment',
      });
      expect(
        find.text('Conversation ended. 2 open reports were resolved.'),
        findsOneWidget,
      );
      expect(
        find.text('Conversation ended by Amal Admin (you)'),
        findsOneWidget,
      );
    });

    testWidgets('already ended conversation: End is disabled, dismiss stays', (
      tester,
    ) async {
      seed();
      detail[r1] = details(reports.first, restricted: true);
      await openDetail(tester, r1);
      expect(
        find.textContaining('has already ended this conversation'),
        findsOneWidget,
      );
      final end = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End conversation'),
      );
      expect(end.onPressed, isNull);
      expect(find.text('Dismiss report'), findsOneWidget);
    });

    testWidgets('unavailable conversation: End is disabled', (tester) async {
      seed();
      detail[r1] = details(reports.first, conversationExists: false);
      await openDetail(tester, r1);
      expect(
        find.textContaining('The conversation is no longer available'),
        findsOneWidget,
      );
      final end = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'End conversation'),
      );
      expect(end.onPressed, isNull);
    });
  });

  group('Validation and messages', () {
    test('decision reasons follow the server rule (1-500)', () {
      expect(
        validateDismissReason('  '),
        'Explain why this report is dismissed',
      );
      expect(
        validateEndConversationReason(null),
        'Explain why this conversation is ended',
      );
      expect(validateDismissReason('x' * 501), 'Use at most 500 characters');
      expect(validateDismissReason('x' * 500), isNull);
      expect(validateEndConversationReason(' ok '), isNull);
    });

    test('server error codes have friendly messages', () {
      String msg(String code) =>
          friendlyError(PostgrestException(message: code, code: 'P0001'));
      expect(msg('report_already_decided'), contains('already decided'));
      expect(msg('report_not_found'), contains('no longer exists'));
      expect(msg('conversation_already_restricted'), contains('already ended'));
      expect(msg('conversation_unavailable'), contains('no longer available'));
      expect(msg('invalid_report_decision_note'), contains('500'));
      // Razan's member-side messages are unchanged.
      expect(msg('already_reported'), 'You already reported this message.');
    });

    test('service validates before calling the server', () async {
      await expectLater(
        SupabaseService.dismissReport(reportId: r1, reason: ' '),
        throwsArgumentError,
      );
      await expectLater(
        SupabaseService.endReportedConversation(reportId: r1, reason: ''),
        throwsArgumentError,
      );
      expect(count('admin_dismiss_report'), 0);
      expect(count('admin_end_reported_conversation'), 0);
    });
  });
}
