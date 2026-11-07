// Admin report management UI (US1-US5). Supabase is replaced by a mock HTTP
// client; no network or database is used. Server rules are covered by
// tests/database/admin_reports_test.mjs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/backend/services/supabase_service.dart';
import 'package:maak_app/backend/validation/form_policy.dart';
import 'package:maak_app/frontend/redesign/admin.dart';
import 'package:maak_app/frontend/redesign/admin_report_media.dart';
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

// Platform players need a device; these record what the viewer asks for.
class _FakeAudio implements AdminAudioSession {
  static final log = <String>[];
  static bool fail = false;
  final _done = StreamController<void>.broadcast();
  @override
  Stream<void> get completed => _done.stream;
  @override
  Future<void> play(String url) async {
    if (fail) throw Exception('decoder failed');
    log.add('play $url');
  }

  @override
  Future<void> pause() async => log.add('pause');
  @override
  Future<void> resume() async => log.add('resume');
  @override
  Future<void> close() async => _done.close();
}

class _FakeVideo extends ChangeNotifier implements AdminVideoSession {
  _FakeVideo(this.url) {
    opened.add(url);
  }
  static final opened = <Uri>[];
  static bool failInit = false;
  final Uri url;
  bool _playing = false;
  @override
  Future<void> initialize() async {
    if (failInit) throw Exception('codec not supported');
  }

  @override
  double get aspectRatio => 16 / 9;
  @override
  bool get isPlaying => _playing;
  @override
  bool get hasError => false;
  @override
  Future<void> play() async {
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Widget view() => const ColoredBox(
    key: ValueKey('fake_video_surface'),
    color: Colors.black,
  );
  @override
  Future<void> close() async {}
}

// 1x1 PNG, and bytes that are not an image.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
final _notAnImage = Uint8List.fromList([1, 2, 3, 4]);

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
  var restrictionHistory = <Map<String, dynamic>>[];
  var media = <String, Map<String, dynamic>>{};
  // Storage sign requests: (object path, expiresIn).
  final signed = <(String, Object?)>[];
  final missingFiles = <String>{};

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
        if (request.url.path.contains('/storage/v1/object/sign/')) {
          // Like Storage: signs only an existing object the caller may read.
          final path = request.url.path.split('/object/sign/chat-media/').last;
          signed.add((path, params?['expiresIn']));
          final gone = missingFiles.contains(path);
          return http.Response(
            jsonEncode(
              gone
                  ? {
                      'statusCode': '404',
                      'error': 'not_found',
                      'message': 'Object not found',
                    }
                  : {
                      'signedURL':
                          '/object/sign/chat-media/$path?token=short-lived',
                    },
            ),
            gone ? 400 : 200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
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
        } else if (name == 'admin_report_media') {
          data = media[params!['p_report_id']];
        } else if (name == 'admin_conversation_restriction_history') {
          data = restrictionHistory;
        } else if (name == 'admin_lift_conversation_restriction') {
          // Like the database: clears the restriction, records the lift.
          final requestId = params!['p_request_id'];
          for (final id in detail.keys.toList()) {
            if (detail[id]!['request_id'] != requestId) continue;
            detail[id] = {
              ...detail[id]!,
              'conversation': {
                ...(detail[id]!['conversation'] as Map),
                'restricted_at': null,
                'restriction_reason': null,
                'restricted_by_name': null,
              },
            };
          }
          restrictionHistory = [
            {
              'id': 'h2',
              'action': 'lifted',
              'reason': params['p_reason'],
              'actor_name': 'Amal Admin',
              'actor_is_me': true,
              'created_at': '2026-11-07T09:00:00Z',
            },
            ...restrictionHistory,
          ];
          data = {'request_id': requestId, 'lifted': true};
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
    restrictionHistory = [];
    media = {};
    signed.clear();
    missingFiles.clear();
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
      // Dismissed reads as resolved: the soft success green.
      final chip = tester.widget<Container>(
        find.byKey(const ValueKey('report_status_dismissed')),
      );
      expect(
        (chip.decoration as BoxDecoration).color,
        AppColors.success.withValues(alpha: 0.10),
      );
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
      expect(
        find.textContaining('Only admins see your reason.'),
        findsOneWidget,
      );
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

  group('Lift restriction', () {
    Future<void> tapLift(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('lift_restriction_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lift_restriction_button')));
      await tester.pumpAndSettle();
    }

    testWidgets('only a restricted conversation offers Lift restriction', (
      tester,
    ) async {
      seed();
      await openDetail(tester, r1);
      expect(
        find.byKey(const ValueKey('lift_restriction_button')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox()); // fresh page state
      await openDetail(tester, r3);
      expect(
        find.byKey(const ValueKey('lift_restriction_button')),
        findsOneWidget,
      );
    });

    testWidgets('requires a reason, lifts, notifies, and records history', (
      tester,
    ) async {
      seed();
      restrictionHistory = [
        {
          'id': 'h1',
          'action': 'restricted',
          'reason': 'Harassment',
          'actor_name': 'Basma Admin',
          'actor_is_me': false,
          'created_at': '2026-11-06T08:00:00Z',
        },
      ];
      await openDetail(tester, r3);
      expect(find.text('Restriction history'), findsOneWidget);
      expect(
        find.text('Conversation restricted by Basma Admin'),
        findsOneWidget,
      );
      await tapLift(tester);
      expect(find.text('Lift this restriction?'), findsOneWidget);
      expect(find.textContaining('without your reason'), findsOneWidget);
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).actionsAlignment,
        MainAxisAlignment.center,
      );
      await tester.tap(confirm('Lift restriction'));
      await tester.pumpAndSettle();
      expect(
        find.text('Explain why the restriction is lifted'),
        findsOneWidget,
      );
      expect(count('admin_lift_conversation_restriction'), 0);
      await tester.enterText(
        inDialog(find.byType(TextField)),
        ' Restricted by mistake ',
      );
      await tester.tap(confirm('Lift restriction'));
      await settle(tester);
      expect(bodies['admin_lift_conversation_restriction'], {
        'p_request_id': '60000000-0000-0000-0000-0000000000c1',
        'p_reason': 'Restricted by mistake',
      });
      expect(
        find.text('Restriction lifted. Both participants were notified.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lift_restriction_button')),
        findsNothing,
      );
      expect(find.text('Ended by an administrator'), findsNothing);
      expect(
        find.text('Restriction lifted by Amal Admin (you)'),
        findsOneWidget,
      );
      expect(find.text('Restricted by mistake'), findsOneWidget);
    });

    testWidgets('a restriction already lifted elsewhere is explained', (
      tester,
    ) async {
      seed();
      await openDetail(tester, r3);
      overrides['admin_lift_conversation_restriction'] = (
        400,
        {'code': 'P0001', 'message': 'conversation_not_restricted'},
      );
      await tapLift(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Not needed');
      await tester.tap(confirm('Lift restriction'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('This restriction changed elsewhere'),
        findsOneWidget,
      );
    });

    test('lift reason follows the server rule', () {
      expect(validateLiftReason(' '), 'Explain why the restriction is lifted');
      expect(validateLiftReason('x' * 501), 'Use at most 500 characters');
      expect(validateLiftReason('ok'), isNull);
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
        find.textContaining('Resolves all 2 open reports here.'),
        findsOneWidget,
      );
      expect(
        find.text("Don't name the reporter or include health details."),
        findsOneWidget,
      );
      // Dialog buttons are centred.
      expect(
        tester.widget<AlertDialog>(find.byType(AlertDialog)).actionsAlignment,
        MainAxisAlignment.center,
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

  group('Report media', () {
    const reportedPath = 'c1/u2/reported.png';
    const voicePath = 'c1/u1/voice.wav';
    const videoPath = 'c1/u2/video.mp4';
    final images = <String>[];
    final originalAudio = AdminReportMediaPlayers.audio;
    final originalVideo = AdminReportMediaPlayers.video;
    final originalImage = AdminReportMediaPlayers.image;
    setUp(() {
      images.clear();
      _FakeAudio.log.clear();
      _FakeAudio.fail = false;
      _FakeVideo.opened.clear();
      _FakeVideo.failInit = false;
      AdminReportMediaPlayers.audio = _FakeAudio.new;
      AdminReportMediaPlayers.video = _FakeVideo.new;
      AdminReportMediaPlayers.image = (url) {
        images.add(url);
        return MemoryImage(_png);
      };
    });
    tearDown(() {
      AdminReportMediaPlayers.audio = originalAudio;
      AdminReportMediaPlayers.video = originalVideo;
      AdminReportMediaPlayers.image = originalImage;
    });

    Map<String, dynamic> item(
      String type,
      String? path, {
      bool available = true,
      String? reason,
      String? mime,
      int? durationMs,
    }) => {
      'message_type': type,
      'mime':
          mime ??
          {
            'image': 'image/png',
            'voice': 'audio/wav',
            'video': 'video/mp4',
          }[type],
      'duration_ms': durationMs,
      'available': available,
      'path': available ? path : null,
      'unavailable_reason': available ? null : reason,
    };

    Map<String, dynamic> ctx(
      String id,
      String type,
      String body, {
      bool reported = false,
    }) => {
      'message_id': id,
      'body': body,
      'message_type': type,
      'created_at': '2026-11-05T09:55:00Z',
      'deleted': false,
      'is_reported': reported,
      'sender': reported ? 'reported' : 'reporter',
    };

    // A photo report r1 whose context holds a voice message, a video and a
    // photo the server did not return (outside the allowed media).
    void seedMedia({
      String status = 'open',
      Map<String, dynamic>? reported,
      List<Map<String, dynamic>>? context,
      String caption = 'Is this okay to send?',
    }) {
      final row = {
        ...reportRow(r1, status: status, preview: caption),
        'message_type': 'image',
      };
      reports = [row];
      detail[r1] = {
        ...details(row),
        'attachment_present': true,
        'context': [
          ctx('mv', 'voice', 'Voice message'),
          ctx('mr', 'image', caption, reported: true),
          ctx('mx', 'video', 'Video'),
          ctx('mi', 'image', 'Photo'),
        ],
      };
      final open = status == 'open';
      media[r1] = {
        'report_id': r1,
        'conversation_exists': true,
        'context_media_allowed': open,
        'reported':
            reported ??
            {
              ...item('image', reportedPath),
              'message_id': 'mr',
              'deleted_for_everyone': false,
            },
        'context':
            context ??
            (open
                ? [
                    {
                      ...item('voice', voicePath, durationMs: 4000),
                      'message_id': 'mv',
                    },
                    {...item('video', videoPath), 'message_id': 'mx'},
                  ]
                : []),
      };
    }

    testWidgets('reported photo loads from a 60-second signed URL', (
      tester,
    ) async {
      seedMedia();
      await openDetail(tester, r1);
      expect(count('admin_report_media'), 1);
      expect(bodies['admin_report_media'], {'p_report_id': r1});
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('report_media_reported')),
          matching: find.byKey(const ValueKey('report_media_image')),
        ),
        findsOneWidget,
      );
      expect(signed, contains((reportedPath, 60)));
      expect(images.first, contains('/storage/v1/object/sign/chat-media/'));
      expect(images.first, contains('token='));
      expect(images.any((u) => u.contains('/object/public/')), isFalse);
      expect(find.text('Is this okay to send?'), findsOneWidget);
      expect(find.textContaining('not shown to administrators'), findsNothing);
      // Only paths the server returned are ever signed.
      expect(signed.map((s) => s.$1).toSet(), isNot(contains(contains('mi'))));
      expect(find.text('Photo (not available)'), findsOneWidget);
      expect(
        find.text('Photo (shown above in the reported message)'),
        findsOneWidget,
      );
    });

    testWidgets('open report: context voice plays, pauses and resumes', (
      tester,
    ) async {
      seedMedia();
      await openDetail(tester, r1);
      final voice = find.byKey(const ValueKey('report_media_context_mv'));
      expect(
        find.descendant(of: voice, matching: find.text('Voice message · 4s')),
        findsOneWidget,
      );
      final play = find.descendant(
        of: voice,
        matching: find.byKey(const ValueKey('report_media_play')),
      );
      await tester.tap(play);
      await settle(tester);
      expect(_FakeAudio.log.single, startsWith('play https://'));
      expect(_FakeAudio.log.single, contains('chat-media/$voicePath?token='));
      expect(signed, contains((voicePath, 60)));
      expect(find.text('Playing voice message'), findsOneWidget);
      await tester.tap(play);
      await settle(tester);
      await tester.tap(play);
      await settle(tester);
      expect(_FakeAudio.log.skip(1), ['pause', 'resume']);
    });

    testWidgets('open report: context video opens a player and plays', (
      tester,
    ) async {
      seedMedia();
      await openDetail(tester, r1);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('report_media_context_mx')),
          matching: find.byKey(const ValueKey('report_media_video_open')),
        ),
      );
      await settle(tester);
      expect(find.text('Reported video'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake_video_surface')), findsOneWidget);
      expect(_FakeVideo.opened.single.path, endsWith('chat-media/$videoPath'));
      expect(signed, contains((videoPath, 60)));
      await tester.tap(find.byKey(const ValueKey('report_media_play')));
      await settle(tester);
      expect(find.byTooltip('Pause video'), findsOneWidget);
    });

    testWidgets('decided report: reported media kept, context media explained', (
      tester,
    ) async {
      seedMedia(status: 'dismissed');
      await openDetail(tester, r1);
      expect(find.byKey(const ValueKey('report_media_image')), findsOneWidget);
      expect(
        find.text(
          'Voice message (context media is shown only while the report is open)',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Video (context media is shown only while the report is open)',
        ),
        findsOneWidget,
      );
      expect(signed.map((s) => s.$1), [reportedPath]);
    });

    testWidgets('deleted conversation and removed file show clear messages', (
      tester,
    ) async {
      seedMedia(
        reported: {
          ...item(
            'image',
            null,
            available: false,
            reason: 'conversation_deleted',
          ),
          'message_id': 'mr',
          'deleted_for_everyone': false,
        },
        context: [
          {
            ...item(
              'voice',
              voicePath,
              available: false,
              reason: 'file_missing',
            ),
            'message_id': 'mv',
          },
        ],
      );
      await openDetail(tester, r1);
      expect(
        find.text(
          'Photo is no longer available because the conversation was deleted.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Voice message is no longer available. The file was removed.',
        ),
        findsOneWidget,
      );
      expect(
        signed,
        isEmpty,
        reason: 'nothing is signed for unavailable media',
      );
    });

    testWidgets('unsupported type is never loaded', (tester) async {
      seedMedia(
        reported: {
          ...item('image', 'c1/u2/reported.gif', mime: 'image/gif'),
          'message_id': 'mr',
          'deleted_for_everyone': false,
        },
        context: [],
      );
      await openDetail(tester, r1);
      expect(
        find.text("This media type can't be shown in the app."),
        findsOneWidget,
      );
      expect(signed, isEmpty);
    });

    testWidgets('refused signing shows Retry, which signs a fresh URL', (
      tester,
    ) async {
      seedMedia(context: []);
      missingFiles.add(reportedPath);
      await openDetail(tester, r1);
      expect(find.text('This media is no longer available.'), findsOneWidget);
      missingFiles.clear();
      await tester.tap(find.byKey(const ValueKey('report_media_retry')));
      await settle(tester);
      expect(find.byKey(const ValueKey('report_media_image')), findsOneWidget);
      expect(signed.where((s) => s.$1 == reportedPath).length, 2);
    });

    testWidgets('offline signing and a damaged photo both offer Retry', (
      tester,
    ) async {
      seedMedia(context: []);
      offline.add('reported.png');
      await openDetail(tester, r1);
      expect(
        find.text(
          'Could not load this media. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      offline.clear();
      AdminReportMediaPlayers.image = (_) => MemoryImage(_notAnImage);
      await tester.tap(find.byKey(const ValueKey('report_media_retry')));
      await settle(tester);
      expect(
        find.text(
          'Could not load this photo. It may be damaged or no longer available.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('voice and video playback failures show errors and recover', (
      tester,
    ) async {
      seedMedia();
      _FakeAudio.fail = true;
      await openDetail(tester, r1);
      final play = find.descendant(
        of: find.byKey(const ValueKey('report_media_context_mv')),
        matching: find.byKey(const ValueKey('report_media_play')),
      );
      await tester.tap(play);
      await settle(tester);
      expect(
        find.text(
          'Could not load this media. Check your connection and try again. Tap play to retry.',
        ),
        findsOneWidget,
      );
      _FakeAudio.fail = false;
      await tester.tap(play);
      await settle(tester);
      expect(_FakeAudio.log.single, startsWith('play '));
      expect(find.byKey(const ValueKey('report_media_error')), findsNothing);

      _FakeVideo.failInit = true;
      await tester.tap(find.byKey(const ValueKey('report_media_video_open')));
      await settle(tester);
      expect(
        find.text(
          'Could not play this video. It may be damaged, unsupported on this device, or no longer available.',
        ),
        findsOneWidget,
      );
      _FakeVideo.failInit = false;
      await tester.tap(find.byKey(const ValueKey('report_media_retry')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fake_video_surface')), findsOneWidget);
    });

    testWidgets(
      'database without the media migration keeps a safe placeholder',
      (tester) async {
        seedMedia();
        overrides['admin_report_media'] = (
          404,
          {'code': 'PGRST202', 'message': 'Could not find the function'},
        );
        await openDetail(tester, r1);
        expect(
          find.text('Photo (could not be loaded. Refresh to try again.)'),
          findsOneWidget,
        );
        expect(find.text('Voice message (not available)'), findsOneWidget);
        expect(signed, isEmpty);
        expect(find.text('Is this okay to send?'), findsOneWidget);
      },
    );

    testWidgets('text reports never request media', (tester) async {
      seed();
      await openDetail(tester, r1);
      expect(count('admin_report_media'), 0);
      expect(signed, isEmpty);
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
