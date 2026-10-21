import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/backend/services/supabase_service.dart';
import 'package:maak_app/frontend/auth/auth_gate.dart';
import 'package:maak_app/frontend/auth/blocked_account_screen.dart';
import 'package:maak_app/frontend/redesign/admin.dart';
import 'package:maak_app/frontend/redesign/feedback.dart';
import 'package:maak_app/frontend/redesign/ui.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';
import 'package:maak_app/frontend/widgets/maak_bottom_nav.dart';

class _PkceStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

const adminId = '20000000-0000-0000-0000-000000000001';
const seekerId = '20000000-0000-0000-0000-000000000002';
const volunteerId = '20000000-0000-0000-0000-000000000003';
const laylaId = '20000000-0000-0000-0000-000000000004';

const _profiles = {
  adminId: {
    'full_name': 'Admin One',
    'username': 'admin_one',
    'email': 'admin@example.com',
    'role': 'admin',
    'created_at': '2026-09-01T08:00:00Z',
    'volunteer_status': null,
  },
  seekerId: {
    'full_name': 'Huda Ali',
    'username': 'huda',
    'email': 'huda@example.com',
    'role': 'help_seeker',
    'created_at': '2026-09-10T08:00:00Z',
    'volunteer_status': null,
  },
  volunteerId: {
    'full_name': 'Omar Saleh',
    'username': 'omar',
    'email': 'omar@example.com',
    'role': 'volunteer',
    'created_at': '2026-09-12T08:00:00Z',
    'volunteer_status': 'approved',
  },
  laylaId: {
    'full_name': 'Layla Haddad',
    'username': 'layla',
    'email': 'layla@example.com',
    'role': 'help_seeker',
    'created_at': '2026-09-14T08:00:00Z',
    'volunteer_status': null,
  },
};

/// In-memory stand-in for the moderation tables, mutated by the block and
/// reactivate RPCs exactly like the database, so refreshes return new state.
class _ModerationStore {
  final blocks = <String, Map<String, dynamic>>{};
  final history = <String, List<Map<String, dynamic>>>{};

  _ModerationStore() {
    blocks[volunteerId] = {
      'user_id': volunteerId,
      'reason': 'Repeated spam messages',
      'blocked_at': '2026-10-18T09:30:00Z',
      // As 20261022 returns it: a verified label, no blocker UUID.
      'blocked_by_name': 'Admin One',
      'blocked_by_is_me': true,
      'times_blocked': 2,
    };
    history[volunteerId] = [
      _event('blocked', 'Repeated spam messages', '2026-10-18T09:30:00Z'),
      _event('reactivated', 'Appeal accepted', '2026-10-10T09:30:00Z'),
      _event('blocked', 'First warning ignored', '2026-10-01T09:30:00Z'),
    ];
  }

  static Map<String, dynamic> _event(
    String action,
    String? reason,
    String at,
  ) => {
    'id': '$action-$at',
    'action': action,
    'reason': reason,
    'actor_name': 'Admin One',
    'actor_is_me': true,
    'created_at': at,
  };

  Map<String, dynamic> account(String id) => {
    'user_id': id,
    ..._profiles[id]!,
    'is_blocked': blocks.containsKey(id),
    'blocked_at': blocks[id]?['blocked_at'],
    'can_block': !blocks.containsKey(id),
  };

  // Like admin_list_accounts() after 20261022: members only, never admins.
  List<Map<String, dynamic>> get accounts => [
    for (final id in _profiles.keys)
      if (_profiles[id]!['role'] != 'admin') account(id),
  ];

  (int, Object?) block(String id, String reason) {
    if (blocks.containsKey(id)) {
      return (400, {'code': 'P0001', 'message': 'already_blocked'});
    }
    final at = DateTime.utc(2026, 10, 20, 12).toIso8601String();
    final times =
        (history[id] ?? []).where((e) => e['action'] == 'blocked').length + 1;
    blocks[id] = {
      'user_id': id,
      'reason': reason,
      'blocked_at': at,
      'blocked_by_name': 'Admin One',
      'blocked_by_is_me': true,
      'times_blocked': times,
    };
    history.putIfAbsent(id, () => []).insert(0, _event('blocked', reason, at));
    return (200, null);
  }

  (int, Object?) reactivate(String id, String? note) {
    if (blocks.remove(id) == null) {
      return (400, {'code': 'P0001', 'message': 'not_blocked'});
    }
    history
        .putIfAbsent(id, () => [])
        .insert(
          0,
          _event(
            'reactivated',
            note,
            DateTime.utc(2026, 10, 20, 13).toIso8601String(),
          ),
        );
    return (200, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Recorded calls (RPC or table name) and their JSON bodies, in order.
  final calls = <String>[];
  final bodies = <String, Object?>{};
  var store = _ModerationStore();
  // Per-test overrides: name -> (status, body); names that throw offline;
  // names whose response waits until the test completes the Completer.
  var overrides = <String, (int, Object?)>{};
  final offline = <String>{};
  final holds = <String, Completer<void>>{};
  Map<String, dynamic> blockStatus = {'blocked': false};
  // Volunteer applications served to the Admin Overview.
  var applications = <Map<String, dynamic>>[];
  Map<String, dynamic> pendingApplication(int n, String name) => {
    'user_id': '30000000-0000-0000-0000-00000000000$n',
    'status': 'pending_review',
    'condition_experience': 'Diabetes',
    'profiles': {'full_name': name, 'username': name.toLowerCase()},
  };

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
        final body = request.body.isEmpty ? null : jsonDecode(request.body);
        calls.add(name);
        bodies[name] = body;
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
              'user_metadata': {'full_name': 'Admin One'},
            },
          };
        } else if (name == 'my_block_status') {
          data = blockStatus;
        } else if (name == 'my_appeal_status') {
          // Appeals are covered by account_appeals_test.dart; here the
          // appeals migration is treated as not installed.
          status = 404;
          data = {'code': 'PGRST202', 'message': 'Could not find the function'};
        } else if (name == 'profiles') {
          const row = {'role': 'admin', 'full_name': 'Admin One'};
          data = request.headers['accept']?.contains('vnd.pgrst.object') == true
              ? row
              : [row];
        } else if (name == 'admin_volunteer_applications') {
          data = applications;
        } else if (name == 'chronic_conditions') {
          data = [
            {
              'id': '40000000-0000-0000-0000-000000000001',
              'name': 'Diabetes',
              'is_active': true,
              'sort_order': 1,
            },
          ];
        } else if (name == 'admin_list_accounts') {
          data = store.accounts;
        } else if (name == 'admin_blocked_accounts') {
          data = store.blocks.values.toList();
        } else if (name == 'admin_account_moderation_history') {
          data = store.history[(body as Map)['p_user_id']] ?? [];
        } else if (name == 'admin_block_account') {
          final params = body as Map;
          (status, data) = store.block(params['p_user_id'], params['p_reason']);
        } else if (name == 'admin_reactivate_account') {
          final params = body as Map;
          (status, data) = store.reactivate(
            params['p_user_id'],
            params['p_note'],
          );
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
    store = _ModerationStore();
    overrides = {};
    offline.clear();
    holds.clear();
    blockStatus = {'blocked': false};
    applications = [];
  });
  tearDownAll(() => Supabase.instance.dispose());

  // Lets the mocked HTTP responses (decoded off the fake clock) arrive.
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
  // Phone width, tall enough that ListView builds the whole detail page.
  const tallPhone = Size(390, 1800);

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);
  Finder confirmButton(String label) =>
      inDialog(find.widgetWithText(FilledButton, label));
  Future<void> openDialog(WidgetTester tester, String action) async {
    await tester.ensureVisible(find.text(action));
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  int count(String name) => calls.where((c) => c == name).length;

  group('SupabaseService moderation calls', () {
    test('blank block reason is rejected before any request', () async {
      await expectLater(
        SupabaseService.blockAccount(userId: seekerId, reason: '  \n '),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isNot(contains('admin_block_account')));
    });
    test('block sends the trimmed reason for the chosen account', () async {
      await SupabaseService.blockAccount(
        userId: seekerId,
        reason: '  Abusive language \n',
      );
      expect(bodies['admin_block_account'], {
        'p_user_id': seekerId,
        'p_reason': 'Abusive language',
      });
    });
    test('note over 500 characters is rejected before any request', () async {
      await expectLater(
        SupabaseService.reactivateAccount(userId: volunteerId, note: 'a' * 501),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isNot(contains('admin_reactivate_account')));
    });
    test('reactivation sends no note when the note is blank', () async {
      await SupabaseService.reactivateAccount(userId: volunteerId, note: '  ');
      expect(bodies['admin_reactivate_account'], {
        'p_user_id': volunteerId,
        'p_note': null,
      });
    });
    test('my block status is null for an active account', () async {
      expect(await SupabaseService.getMyBlockStatus(), isNull);
    });
    test('my block status returns the reason for a blocked account', () async {
      blockStatus = {
        'blocked': true,
        'reason': 'Spam',
        'blocked_at': '2026-10-18T09:30:00Z',
      };
      expect((await SupabaseService.getMyBlockStatus())!['reason'], 'Spam');
    });
    test('missing blocking migration is treated as not blocked', () async {
      overrides['my_block_status'] = (
        404,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
      );
      expect(await SupabaseService.getMyBlockStatus(), isNull);
    });
    test(
      'other status failures are rethrown, never treated as active',
      () async {
        overrides['my_block_status'] = (
          500,
          {'code': '57014', 'message': 'canceling statement'},
        );
        await expectLater(
          SupabaseService.getMyBlockStatus(),
          throwsA(isA<PostgrestException>()),
        );
      },
    );
  });

  test('new database error codes have friendly messages', () {
    String message(String code) =>
        friendlyError(PostgrestException(message: code, code: 'P0001'));
    expect(message('account_blocked'), contains('has been blocked'));
    expect(message('participant_unavailable'), contains('not available'));
    expect(message('cannot_block_self'), 'You cannot block your own account.');
    expect(
      message('cannot_block_admin'),
      'Administrator accounts cannot be blocked.',
    );
    expect(message('already_blocked'), contains('already blocked'));
    expect(message('not_blocked'), contains('already active'));
    expect(message('invalid_block_reason'), contains('500 characters'));
    expect(message('account_not_found'), contains('no longer exists'));
    expect(message('request_participants_immutable'), contains('Refresh'));
    expect(message('request_link_immutable'), contains('Refresh'));
    // Unrelated codes keep their existing messages.
    expect(message('not_allowed'), contains('Sign in with an account'));
  });

  group('Admin overview', () {
    testWidgets(
      'Manage accounts card opens Accounts and selects its tab; others remain',
      (tester) async {
        await pumpAt(tester, const AdminShell(), phone);
        expect(find.text('Volunteer applications'), findsOneWidget);
        expect(find.text('Chronic conditions'), findsOneWidget);
        expect(find.byTooltip('Log out'), findsOneWidget);
        final card = find.text('Manage accounts');
        expect(card, findsOneWidget);
        expect(find.text('Block or reactivate accounts'), findsOneWidget);
        // Same component and icon treatment as the existing navigation cards.
        Finder cardOf(String title) => find.ancestor(
          of: find.text(title),
          matching: find.byType(SurfaceCard),
        );
        expect(cardOf('Manage accounts'), findsOneWidget);
        // Compared with the existing card by style, not height: the test font
        // wraps longer titles, so heights depend on text length here.
        final mine = tester.widget<SurfaceCard>(cardOf('Manage accounts'));
        final theirs = tester.widget<SurfaceCard>(cardOf('Chronic conditions'));
        expect(mine.padding, theirs.padding);
        expect(
          tester.getSize(cardOf('Manage accounts')).width,
          tester.getSize(cardOf('Chronic conditions')).width,
        );
        Icon iconIn(String title, IconData data) => tester.widget<Icon>(
          find.descendant(of: cardOf(title), matching: find.byIcon(data)),
        );
        final icon = iconIn('Manage accounts', Icons.manage_accounts_outlined);
        final existing = iconIn('Chronic conditions', Icons.favorite_border);
        expect(icon.size, existing.size);
        expect(icon.color, existing.color);
        expect(iconIn('Manage accounts', Icons.chevron_right), isNotNull);
        Text textIn(String title, String text) => tester.widget<Text>(
          find.descendant(of: cardOf(title), matching: find.text(text)),
        );
        expect(
          textIn('Manage accounts', 'Manage accounts').style,
          textIn('Chronic conditions', 'Chronic conditions').style,
        );
        expect(
          textIn('Manage accounts', 'Block or reactivate accounts').style,
          textIn('Chronic conditions', 'Manage condition types').style,
        );

        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await settle(tester);
        expect(
          find.text('Search by name, email or username...'),
          findsOneWidget,
        );
        // The bottom navigation highlights Accounts, as when its tab is tapped.
        final navLabel = tester.widget<Text>(
          find.descendant(
            of: find.byType(MaakBottomNav),
            matching: find.text('Accounts'),
          ),
        );
        expect(navLabel.style?.fontWeight, FontWeight.w700);
        expect(tester.takeException(), isNull);
      },
    );

    for (final entry in {
      'small phone, large text': (smallPhone, 1.5),
      'tablet': (tablet, 1.0),
    }.entries) {
      testWidgets('overview with the new card fits a ${entry.key}', (
        tester,
      ) async {
        final (size, scale) = entry.value;
        await pumpAt(tester, const AdminShell(), size, textScale: scale);
        await tester.ensureVisible(find.text('Manage accounts'));
        await tester.pumpAndSettle();
        expect(find.text('Manage accounts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Admin overview pull-to-refresh', () {
    // Drags down from the top of the Overview far enough to trigger a refresh.
    Future<void> pull(WidgetTester tester) async {
      await tester.fling(
        find.text('Admin overview'),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Finder overviewCards() => find.byWidgetPredicate(
      (w) =>
          w is Text &&
          const [
            'Volunteer applications',
            'Chronic conditions',
            'Manage accounts',
          ].contains(w.data),
    );

    for (final entry in {
      'phone': (phone, false),
      'phone with short content': (const Size(390, 1400), true),
      'tablet with short content': (const Size(1024, 1366), true),
    }.entries) {
      testWidgets('${entry.key}: pulling refreshes the Overview in place', (
        tester,
      ) async {
        final (size, short) = entry.value;
        await pumpAt(tester, const AdminShell(), size);
        expect(find.text('Sami Noor'), findsNothing);
        expect(count('admin_volunteer_applications'), 1);
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        if (short) {
          expect(
            scrollable.position.maxScrollExtent,
            0,
            reason: 'content is shorter than the screen',
          );
        }
        // Same indicator and physics as the other Admin pages.
        final indicator = tester.widget<RefreshIndicator>(
          find.byType(RefreshIndicator),
        );
        expect(indicator.color, isNull);
        expect(indicator.backgroundColor, isNull);
        expect(
          tester.widget<ListView>(find.byType(ListView).first).physics,
          isA<AlwaysScrollableScrollPhysics>(),
        );

        applications = [pendingApplication(1, 'Sami Noor')];
        await pull(tester);
        await settle(tester);
        expect(count('admin_volunteer_applications'), 2);
        expect(count('chronic_conditions'), 2);
        expect(find.text('Sami Noor'), findsOneWidget);
        expect(overviewCards(), findsNWidgets(3));
        expect(find.byTooltip('Log out'), findsOneWidget);
        expect(find.text('Overview'), findsOneWidget);
        expect(scrollable.position.pixels, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a failed refresh keeps the content and explains the error', (
      tester,
    ) async {
      applications = [pendingApplication(1, 'Sami Noor')];
      await pumpAt(tester, const AdminShell(), phone);
      expect(find.text('Sami Noor'), findsOneWidget);

      offline.add('admin_volunteer_applications');
      await pull(tester);
      await settle(tester);
      expect(find.text('Please check this'), findsOneWidget);
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // Previously loaded figures and all three cards are still shown.
      expect(find.text('Sami Noor'), findsOneWidget);
      expect(overviewCards(), findsNWidgets(3));
      expect(find.text('Could not load overview'), findsNothing);
      // No automatic retry.
      await tester.pump(const Duration(seconds: 30));
      expect(count('admin_volunteer_applications'), 2);

      // Try again in the error dialog refreshes once more.
      offline.clear();
      applications = [
        pendingApplication(1, 'Sami Noor'),
        pendingApplication(2, 'Lina Fares'),
      ];
      await pull(tester);
      await settle(tester);
      expect(find.text('Lina Fares'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pulling during a load does not start another request', (
      tester,
    ) async {
      holds['admin_volunteer_applications'] = Completer<void>();
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const AdminShell()),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(count('admin_volunteer_applications'), 1);

      await pull(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await pull(tester);
      await tester.pump();
      expect(count('admin_volunteer_applications'), 1);

      applications = [pendingApplication(1, 'Sami Noor')];
      holds['admin_volunteer_applications']!.complete();
      holds.clear();
      await settle(tester);
      expect(count('admin_volunteer_applications'), 1);
      expect(find.text('Sami Noor'), findsOneWidget);

      // A second pull while a refresh is still running is ignored too.
      holds['admin_volunteer_applications'] = Completer<void>();
      await pull(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await pull(tester);
      await tester.pump();
      expect(count('admin_volunteer_applications'), 2);
      holds['admin_volunteer_applications']!.complete();
      await settle(tester);
      expect(count('admin_volunteer_applications'), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pulling recovers from a failed first load', (tester) async {
      offline.add('admin_volunteer_applications');
      await pumpAt(tester, const AdminShell(), phone);
      expect(find.text('Could not load overview'), findsOneWidget);

      offline.clear();
      applications = [pendingApplication(1, 'Sami Noor')];
      await pull(tester);
      await settle(tester);
      expect(find.text('Could not load overview'), findsNothing);
      expect(find.text('Sami Noor'), findsOneWidget);
      expect(overviewCards(), findsNWidgets(3));
    });

    testWidgets('a pull that fails before any content shows the error screen', (
      tester,
    ) async {
      offline.add('admin_volunteer_applications');
      await pumpAt(tester, const AdminShell(), phone);
      await pull(tester);
      await settle(tester);
      expect(find.text('Could not load overview'), findsOneWidget);
      expect(find.text('Please check this'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Accounts list', () {
    testWidgets('shows accounts, statuses and a two-line reason preview', (
      tester,
    ) async {
      store.blocks[volunteerId]!['reason'] = 'Long reason. ' * 30;
      await pumpAt(tester, const AccountsAdminPage(), phone);
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Active (2)'), findsOneWidget);
      expect(find.text('Blocked (1)'), findsOneWidget);
      final preview = tester.widget<Text>(
        find.textContaining('Blocked 18 Oct 2026: Long reason.'),
      );
      expect(preview.maxLines, 2);
      expect(preview.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search works within All, Active and Blocked', (tester) async {
      await pumpAt(tester, const AccountsAdminPage(), phone);
      Future<void> filter(String label) async {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byType(TextField), 'OMAR');
      await tester.pumpAndSettle();
      expect(find.text('Omar Saleh'), findsOneWidget);
      await filter('Active (2)');
      expect(find.text('Omar Saleh'), findsNothing);
      expect(find.text('No matching accounts'), findsOneWidget);
      await filter('Blocked (1)');
      expect(find.text('Omar Saleh'), findsOneWidget);

      // Matches email and role too, combined with the filter.
      await tester.enterText(find.byType(TextField), 'help seeker');
      await filter('Active (2)');
      expect(find.text('Huda Ali'), findsOneWidget);
      expect(find.text('Layla Haddad'), findsOneWidget);
      expect(find.text('Omar Saleh'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await filter('Blocked (1)');
      expect(find.text('Omar Saleh'), findsOneWidget);
      expect(find.text('Huda Ali'), findsNothing);
      await filter('All (3)');
      expect(find.text('Huda Ali'), findsOneWidget);
      expect(find.text('Layla Haddad'), findsOneWidget);
    });

    testWidgets('admin accounts never appear, even when searched for', (
      tester,
    ) async {
      await pumpAt(tester, const AccountsAdminPage(), phone);
      expect(find.text('Admin One'), findsNothing);
      expect(find.text('Administrator'), findsNothing);
      for (final query in ['admin', 'admin@example.com', 'administrator']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(find.text('Admin One'), findsNothing);
        expect(find.text('No matching accounts'), findsOneWidget);
      }
    });

    testWidgets('empty Blocked filter explains itself', (tester) async {
      store.blocks.clear();
      await pumpAt(tester, const AccountsAdminPage(), phone);
      await tester.tap(find.text('Blocked (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No blocked accounts'), findsOneWidget);
    });

    testWidgets('shows a spinner while loading', (tester) async {
      holds['admin_list_accounts'] = Completer<void>();
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const AccountsAdminPage()),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      holds['admin_list_accounts']!.complete();
      await settle(tester);
      expect(find.text('Huda Ali'), findsOneWidget);
    });

    testWidgets('tablet shows two columns without overflow', (tester) async {
      await pumpAt(tester, const AccountsAdminPage(), tablet);
      final huda = tester.getTopLeft(find.text('Huda Ali'));
      final omar = tester.getTopLeft(find.text('Omar Saleh'));
      expect(omar.dy, huda.dy, reason: 'first two cards share a row');
      expect(omar.dx, greaterThan(huda.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('small phone with large text does not overflow', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const AccountsAdminPage(),
        smallPhone,
        textScale: 1.5,
      );
      expect(find.text('Blocked (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('network failure waits for a manual Try again', (tester) async {
      offline.add('admin_list_accounts');
      await pumpAt(tester, const AccountsAdminPage(), phone);
      expect(find.text('Could not load accounts'), findsOneWidget);
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(count('admin_list_accounts'), 1);

      offline.clear();
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(count('admin_list_accounts'), 2);
      expect(find.text('Huda Ali'), findsOneWidget);
    });

    testWidgets('missing database setup is explained, not shown as a crash', (
      tester,
    ) async {
      overrides['admin_list_accounts'] = (
        404,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
      );
      await pumpAt(tester, const AccountsAdminPage(), phone);
      expect(
        find.textContaining('database setup is incomplete'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('admin shell keeps existing tabs and adds Accounts', (
      tester,
    ) async {
      await pumpAt(tester, const AdminShell(), phone);
      for (final label in ['Overview', 'Applications', 'Conditions']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('Accounts'));
      await settle(tester);
      expect(find.text('Search by name, email or username...'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Action visibility', () {
    testWidgets('active account shows Block only', (tester) async {
      await pumpAt(
        tester,
        AccountDetailPage(account: store.account(seekerId)),
        tallPhone,
      );
      expect(find.text('Block account'), findsOneWidget);
      expect(find.text('Reactivate account'), findsNothing);
    });

    testWidgets('blocked account shows Reactivate only', (tester) async {
      await pumpAt(
        tester,
        AccountDetailPage(
          account: {
            ...store.account(volunteerId),
            'block': store.blocks[volunteerId],
          },
        ),
        tallPhone,
      );
      expect(find.text('Reactivate account'), findsOneWidget);
      expect(find.text('Block account'), findsNothing);
    });

    testWidgets('admin account shows neither action', (tester) async {
      await pumpAt(
        tester,
        AccountDetailPage(account: store.account(adminId)),
        tallPhone,
      );
      expect(find.text('Block account'), findsNothing);
      expect(find.text('Reactivate account'), findsNothing);
      expect(
        find.text('Administrator accounts cannot be blocked.'),
        findsOneWidget,
      );
    });
  });

  group('Blocking and reactivation', () {
    testWidgets(
      'block validates inline, then refreshes status, details and counts',
      (tester) async {
        await pumpAt(tester, const AccountsAdminPage(), tallPhone);
        await tester.tap(find.text('Huda Ali'));
        await settle(tester);
        await openDialog(tester, 'Block account');
        // The selected account is named before confirming.
        expect(inDialog(find.text('Huda Ali')), findsOneWidget);
        expect(inDialog(find.text('huda@example.com')), findsOneWidget);

        await tester.tap(confirmButton('Block account'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter a reason for blocking this account'),
          findsOneWidget,
        );
        expect(count('admin_block_account'), 0);

        await tester.enterText(
          inDialog(find.byType(TextField)),
          '  Abusive language  ',
        );
        await tester.tap(confirmButton('Block account'));
        await settle(tester);

        expect(bodies['admin_block_account'], {
          'p_user_id': seekerId,
          'p_reason': 'Abusive language',
        });
        expect(find.text('Account blocked successfully.'), findsOneWidget);
        // Refreshed from the server: the verified label, with "(you)" only
        // because the server reports this admin as the blocker.
        expect(find.text('Blocking details'), findsOneWidget);
        expect(find.text('Admin One (you)'), findsOneWidget);
        expect(find.text('You'), findsNothing);
        expect(find.text('Abusive language'), findsNWidgets(2));
        expect(find.text('Reactivate account'), findsOneWidget);
        expect(find.text('Block account'), findsNothing);

        await tester.pageBack();
        await settle(tester);
        expect(find.text('Active (1)'), findsOneWidget);
        expect(find.text('Blocked (2)'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('reactivate updates status, history order and counts', (
      tester,
    ) async {
      await pumpAt(tester, const AccountsAdminPage(), tallPhone);
      await tester.tap(find.text('Omar Saleh'));
      await settle(tester);
      // Server order, newest first, is preserved.
      final events = find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'Blocked' || w.data == 'Reactivated'),
      );
      List<String> labels() => [
        for (final e in events.evaluate())
          if ((e.widget as Text).style?.fontWeight == FontWeight.w700)
            (e.widget as Text).data!,
      ];
      expect(labels(), ['Blocked', 'Reactivated', 'Blocked']);

      await openDialog(tester, 'Reactivate account');
      expect(inDialog(find.text('Omar Saleh')), findsOneWidget);
      await tester.enterText(inDialog(find.byType(TextField)), 'Appeal ok');
      await tester.tap(confirmButton('Reactivate account'));
      await settle(tester);

      expect(find.text('Account reactivated successfully.'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Blocking details'), findsNothing);
      expect(find.text('Block account'), findsOneWidget);
      expect(find.text('Reactivate account'), findsNothing);
      expect(labels(), ['Reactivated', 'Blocked', 'Reactivated', 'Blocked']);
      expect(find.text('Appeal ok'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      expect(find.text('Active (3)'), findsOneWidget);
      expect(find.text('Blocked (0)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('double taps while processing send one request', (
      tester,
    ) async {
      holds['admin_block_account'] = Completer<void>();
      await pumpAt(
        tester,
        AccountDetailPage(account: store.account(seekerId)),
        tallPhone,
      );
      await openDialog(tester, 'Block account');
      await tester.enterText(inDialog(find.byType(TextField)), 'Spam');
      await tester.tap(confirmButton('Block account'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      // While waiting: confirm and Cancel are disabled, labelled as busy.
      final busy = inDialog(find.widgetWithText(FilledButton, 'Blocking...'));
      expect(busy, findsOneWidget);
      expect(tester.widget<FilledButton>(busy).onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              inDialog(find.widgetWithText(OutlinedButton, 'Cancel')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(busy, warnIfMissed: false);
      await tester.tap(busy, warnIfMissed: false);
      await tester.pump();
      holds['admin_block_account']!.complete();
      await settle(tester);
      expect(count('admin_block_account'), 1);
      expect(find.text('Account blocked successfully.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('page action is disabled while its dialog is open', (
      tester,
    ) async {
      await pumpAt(
        tester,
        AccountDetailPage(account: store.account(seekerId)),
        tallPhone,
      );
      await openDialog(tester, 'Block account');
      final pageButton = find.ancestor(
        of: find.text('Block account').first,
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(pageButton).onPressed, isNull);
    });

    testWidgets('a block made by another admin is shown instead of an error', (
      tester,
    ) async {
      // The page still shows Huda as active, but the server already blocked her.
      final staleRow = store.account(seekerId);
      store.block(seekerId, 'Blocked by another admin');
      await pumpAt(tester, AccountDetailPage(account: staleRow), tallPhone);
      await openDialog(tester, 'Block account');
      await tester.enterText(inDialog(find.byType(TextField)), 'Spam');
      await tester.tap(confirmButton('Block account'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('Another administrator changed this account'),
        findsOneWidget,
      );
      expect(find.text('Blocked by another admin'), findsNWidgets(2));
      expect(find.text('Reactivate account'), findsOneWidget);
      expect(find.text('Block account'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('network failure keeps the dialog open for manual retry', (
      tester,
    ) async {
      offline.add('admin_block_account');
      await pumpAt(
        tester,
        AccountDetailPage(account: store.account(seekerId)),
        tallPhone,
      );
      await openDialog(tester, 'Block account');
      await tester.enterText(inDialog(find.byType(TextField)), 'Spam');
      await tester.tap(confirmButton('Block account'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
      expect(count('admin_block_account'), 1);

      offline.clear();
      await tester.tap(confirmButton('Block account'));
      await settle(tester);
      expect(count('admin_block_account'), 2);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('dialogs stay usable with the keyboard open on a phone', (
      tester,
    ) async {
      await pumpAt(
        tester,
        AccountDetailPage(account: store.account(seekerId)),
        phone,
      );
      await tester.scrollUntilVisible(
        find.text('Block account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await openDialog(tester, 'Block account');
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final confirm = confirmButton('Block account');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(844 - 340));
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a reason for blocking this account'),
        findsOneWidget,
      );
    });

    testWidgets('tablet places information and blocking details side by side', (
      tester,
    ) async {
      await pumpAt(
        tester,
        AccountDetailPage(
          account: {
            ...store.account(volunteerId),
            'block': store.blocks[volunteerId],
          },
        ),
        tablet,
      );
      final info = tester.getTopLeft(find.text('Account information'));
      final blocking = tester.getTopLeft(find.text('Blocking details'));
      expect(info.dy, blocking.dy);
      expect(blocking.dx, greaterThan(info.dx));
      expect(tester.takeException(), isNull);
    });
  });

  group('Blocked-user screen and routing', () {
    const screen = BlockedAccountScreen(
      reason: 'Repeated spam messages',
      blockedAt: '2026-10-18T09:30:00Z',
    );

    testWidgets('shows heading, reason and date; actions fit on a phone', (
      tester,
    ) async {
      await pumpAt(tester, screen, phone);
      expect(find.text('Your account has been restricted'), findsOneWidget);
      expect(find.text('Repeated spam messages'), findsOneWidget);
      expect(find.text('Restricted on'), findsOneWidget);
      expect(find.text('18 Oct 2026'), findsOneWidget);
      // Reachable without scrolling on a standard phone.
      expect(tester.getRect(find.text('Check again')).bottom, lessThan(844));
      expect(tester.getRect(find.text('Log out')).bottom, lessThan(844));
      // No unsupported promises or invented contact details.
      expect(find.textContaining('safe'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final entry in {
      'small phone, large text': smallPhone,
      'tablet': tablet,
    }.entries) {
      testWidgets('works on ${entry.key}', (tester) async {
        await pumpAt(
          tester,
          screen,
          entry.value,
          textScale: entry.value == smallPhone ? 1.5 : 1,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Log out'));
        await tester.pumpAndSettle();
        expect(find.text('Check again'), findsOneWidget);
        expect(find.text('Log out'), findsOneWidget);
      });
    }

    testWidgets('AuthGate checks block status before any profile routing', (
      tester,
    ) async {
      blockStatus = {
        'blocked': true,
        'reason': 'Repeated spam messages',
        'blocked_at': '2026-10-18T09:30:00Z',
      };
      await pumpAt(tester, const AuthGate(), phone);
      expect(find.byType(BlockedAccountScreen), findsOneWidget);
      expect(find.text('Repeated spam messages'), findsOneWidget);
      expect(calls.first, 'my_block_status');
      expect(calls, isNot(contains('profiles')));
    });

    testWidgets('Check again lets a reactivated account continue', (
      tester,
    ) async {
      blockStatus = {'blocked': true, 'reason': 'Spam', 'blocked_at': null};
      await pumpAt(tester, const AuthGate(), phone);
      expect(find.byType(BlockedAccountScreen), findsOneWidget);
      blockStatus = {'blocked': false};
      await tester.tap(find.text('Check again'));
      await settle(tester);
      expect(find.byType(BlockedAccountScreen), findsNothing);
      expect(find.text('Admin overview'), findsOneWidget);
    });

    testWidgets('AuthGate continues normally for an active account', (
      tester,
    ) async {
      await pumpAt(tester, const AuthGate(), phone);
      expect(find.byType(BlockedAccountScreen), findsNothing);
      expect(find.text('Admin overview'), findsOneWidget);
      expect(
        calls.indexOf('my_block_status'),
        lessThan(calls.indexOf('profiles')),
      );
    });

    testWidgets('AuthGate works before the blocking migration is deployed', (
      tester,
    ) async {
      overrides['my_block_status'] = (
        404,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
      );
      await pumpAt(tester, const AuthGate(), phone);
      expect(find.text('Admin overview'), findsOneWidget);
    });

    testWidgets('AuthGate shows Try again if block status cannot load', (
      tester,
    ) async {
      offline.add('my_block_status');
      await pumpAt(tester, const AuthGate(), phone);
      expect(find.text('Could not load your account'), findsOneWidget);
      expect(find.text('Admin overview'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
