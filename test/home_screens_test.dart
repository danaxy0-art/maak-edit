import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/frontend/design/components.dart';
import 'package:maak_app/frontend/redesign/home.dart';
import 'package:maak_app/frontend/redesign/matching_page.dart';
import 'package:maak_app/frontend/redesign/navigation.dart';
import 'package:maak_app/frontend/redesign/profile.dart';
import 'package:maak_app/frontend/redesign/support.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

// Home for both roles at phone and tablet sizes, text scales and states.
// Screenshots land in test/goldens/home/; behaviour tests check that every
// action still opens the same destination.

enum Scenario { empty, conversation, volunteer, error, loading }

var scenario = Scenario.empty;

List<Map<String, dynamic>> _requests() => switch (scenario) {
  Scenario.conversation => [
    {
      'id': '00000000-0000-0000-0000-0000000000a1',
      'status': 'accepted',
      'contact_name': 'Sara',
      'last_message':
          'Thanks for sharing that. I had the same worry when I was first diagnosed.',
    },
  ],
  Scenario.volunteer => [
    for (var i = 0; i < 3; i++)
      {'id': '00000000-0000-0000-0000-00000000010$i', 'status': 'pending'},
    for (var i = 0; i < 2; i++)
      {
        'id': '00000000-0000-0000-0000-00000000020$i',
        'status': 'accepted',
        'contact_name': 'Layla',
      },
  ],
  _ => [],
};

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
    );
  }
  await loader.load();
}

String _jwt(Map<String, dynamic> payload) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.sig';
}

Future<void> _signIn(String fullName) async {
  final exp = DateTime.now().add(const Duration(days: 1));
  final user = {
    'id': '00000000-0000-0000-0000-000000000001',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'member@example.com',
    'app_metadata': {},
    'user_metadata': {'full_name': fullName},
    'created_at': '2026-01-01T00:00:00Z',
  };
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token': _jwt({
        'sub': user['id'],
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
      }),
      'refresh_token': 'refresh',
      'token_type': 'bearer',
      'expires_in': 86400,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'user': user,
    }),
  );
}

class _ShellCalls {
  final tabs = <int>[];
}

Future<_ShellCalls> _pumpHome(
  WidgetTester tester, {
  required String role,
  Size size = const Size(390, 844),
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final calls = _ShellCalls();
  final theme = AppTheme.light();
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('screen'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: direction, child: child!),
        ),
        home: ShellScope(
          role: role,
          selectTab: calls.tabs.add,
          child: HomePage(role: role),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(MaterialApp));
    await precacheImage(const AssetImage('assets/images/logo.png'), context);
    await precacheImage(
      const AssetImage('assets/images/botanical_background.png'),
      context,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return calls;
}

// The bell's realtime subscription keeps timers alive; close it after each test.
void testHome(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        // Not awaited: unsubscribing waits on timers only pump() advances.
        unawaited(Supabase.instance.client.removeAllChannels());
        await tester.pump(const Duration(minutes: 1));
      }
    });

Future<void> _shot(WidgetTester tester, String name) => expectLater(
  find.byKey(const Key('screen')),
  matchesGoldenFile('goldens/home/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pending = Completer<http.Response>();

  setUpAll(() async {
    await _loadFont('Roboto', ['test/fonts/Roboto-Regular.ttf']);
    await _loadFont('MaakSerif', ['assets/fonts/DMSerifDisplay-Regular.ttf']);
    await _loadFont('DMSans', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/DMSans-$w.ttf',
    ]);
    await _loadFont('MaterialIcons', ['test/fonts/MaterialIcons-Regular.otf']);
    await Supabase.initialize(
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/rpc/my_support_requests')) {
          if (scenario == Scenario.loading) return pending.future;
          if (scenario == Scenario.error) {
            return http.Response(
              jsonEncode({'message': 'unavailable', 'code': '503'}),
              503,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            jsonEncode(_requests()),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
      url: 'https://example.supabase.co',
      publishableKey: 'test-public-key',
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: _MemoryPkceStorage(),
        autoRefreshToken: false,
        persistSession: false,
        localStorage: const EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  const sizes = {
    'phone': Size(390, 844),
    'phone_landscape': Size(844, 390),
    'tablet': Size(834, 1194),
    'tablet_landscape': Size(1194, 834),
  };
  const cases = {
    'seeker_empty': ('help_seeker', Scenario.empty, 'Layla'),
    'seeker_conversation': ('help_seeker', Scenario.conversation, 'Layla'),
    'volunteer': ('volunteer', Scenario.volunteer, 'Omar'),
  };

  for (final c in cases.entries) {
    final (role, data, name) = c.value;
    for (final s in sizes.entries) {
      final scales = s.key == 'phone' || s.key == 'tablet'
          ? [1.0, 1.3, 2.0]
          : [1.0];
      for (final scale in scales) {
        final shot = '${c.key}_${s.key}_${scale}x';
        testHome('$shot renders without overflow', (tester) async {
          scenario = data;
          await tester.runAsync(() => _signIn(name));
          await _pumpHome(tester, role: role, size: s.value, textScale: scale);
          expect(tester.takeException(), isNull);
          await _shot(tester, shot);
        });
      }
    }
    testHome('${c.key} phone scrolls to the end', (tester) async {
      scenario = data;
      await tester.runAsync(() => _signIn(name));
      await _pumpHome(tester, role: role);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _shot(tester, '${c.key}_phone_scrolled');
    });
    testHome('${c.key} lays out right-to-left', (tester) async {
      scenario = data;
      await tester.runAsync(() => _signIn(name));
      await _pumpHome(tester, role: role, direction: TextDirection.rtl);
      expect(tester.takeException(), isNull);
      await _shot(tester, '${c.key}_phone_rtl');
    });
  }

  testHome('load failure explains the problem and offers a retry', (
    tester,
  ) async {
    scenario = Scenario.error;
    await tester.runAsync(() => _signIn('Layla'));
    await _pumpHome(tester, role: 'help_seeker');
    expect(find.text('Could not load your activity'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'seeker_error_phone_1.0x');
  });

  testHome('activity shows a loading state while requests load', (
    tester,
  ) async {
    scenario = Scenario.loading;
    await tester.runAsync(() => _signIn('Layla'));
    await _pumpHome(tester, role: 'help_seeker', settle: false);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Loading your activity',
      ),
      findsOneWidget,
    );
    expect(find.byType(SkeletonBlock), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'seeker_loading_phone_1.0x');
    await tester.pumpWidget(const SizedBox());
  });

  group('actions keep their destinations', () {
    // Destination pages keep spinners running, so wait out the transition only.
    Future<void> settleRoute(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> back(WidgetTester tester) async {
      await tester.pageBack();
      await settleRoute(tester);
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      final target = find.text(text).last;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await settleRoute(tester);
    }

    testHome('help seeker', (tester) async {
      scenario = Scenario.conversation;
      await tester.runAsync(() => _signIn('Layla'));
      final calls = await _pumpHome(tester, role: 'help_seeker');
      expect(find.textContaining('Layla'), findsOneWidget);

      await tapText(tester, 'Find my matches');
      expect(find.byType(MatchingPage), findsOneWidget);
      await back(tester);

      await tapText(tester, 'My journey');
      await tapText(tester, 'Messages');
      expect(calls.tabs, [1, 2]);

      await tapText(tester, 'Resources');
      expect(find.byType(ResourcesPage), findsOneWidget);
      await back(tester);

      await tapText(tester, 'Sara');
      expect(find.byType(ConversationPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testHome('volunteer', (tester) async {
      scenario = Scenario.volunteer;
      await tester.runAsync(() => _signIn('Omar'));
      final calls = await _pumpHome(tester, role: 'volunteer');
      expect(find.text('Volunteer'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tapText(tester, 'Matching preferences');
      expect(find.byType(EditProfilePage), findsOneWidget);
      await back(tester);

      await tapText(tester, 'View requests');
      expect(find.byType(RequestsPage), findsOneWidget);
      await back(tester);

      await tapText(tester, 'Requests');
      expect(find.byType(RequestsPage), findsOneWidget);
      await back(tester);

      await tapText(tester, 'Messages');
      expect(calls.tabs, [2]);

      await tapText(tester, 'Resources');
      expect(find.byType(ResourcesPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> removeItem({required String key}) async => _values.remove(key);
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _values[key] = value;
}
