import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

// Shared setup for screenshot and behaviour tests of redesigned screens:
// fonts, a fake Supabase backend, a signed-in member and realtime cleanup.

/// Answers a request, or returns null to fall back to an empty list.
typedef FakeBackend = Future<http.Response>? Function(http.Request request);

FakeBackend? fakeBackend;

/// Every request the fake backend received in the current test.
final sentRequests = <http.Request>[];

http.Response jsonResponse(
  http.Request request,
  Object body, {
  int status = 200,
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);

/// A response that never arrives, to hold a screen in its loading state.
Future<http.Response> neverResponds() => Completer<http.Response>().future;

/// Builds a backend from path-suffix → body (or `Future<http.Response>
/// Function(http.Request)` for full control).
FakeBackend backendFrom(Map<String, Object> routes) => (request) {
  for (final route in routes.entries) {
    if (!request.url.path.endsWith(route.key)) continue;
    final value = route.value;
    if (value is Future<http.Response> Function(http.Request)) {
      return value(request);
    }
    return Future.value(jsonResponse(request, value));
  }
  return null;
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

Future<void> setUpScreenHarness() async {
  await _loadFont('Roboto', ['test/fonts/Roboto-Regular.ttf']);
  await _loadFont('MaakSerif', ['assets/fonts/DMSerifDisplay-Regular.ttf']);
  await _loadFont('DMSans', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fonts/DMSans-$w.ttf',
  ]);
  await _loadFont('MaterialIcons', ['test/fonts/MaterialIcons-Regular.otf']);
  await Supabase.initialize(
    httpClient: MockClient((request) {
      sentRequests.add(request);
      return fakeBackend?.call(request) ??
          Future.value(jsonResponse(request, []));
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
}

String _jwt(Map<String, dynamic> payload) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.sig';
}

Future<void> signIn(String fullName) async {
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

/// testWidgets with a fresh backend per test and realtime cleanup, which
/// runs even when the body fails so later tests do not inherit timers.
void testScreen(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, (tester) async {
      sentRequests.clear();
      try {
        await body(tester);
      } finally {
        fakeBackend = null;
        await tester.pumpWidget(const SizedBox());
        // Not awaited: unsubscribing waits on timers only pump() advances.
        unawaited(Supabase.instance.client.removeAllChannels());
        await tester.pump(const Duration(minutes: 1));
      }
    });

/// Pumps [home] in the app theme at [size] and lets data arrive. Never waits
/// for the screen to go idle, because loading indicators keep animating.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 844),
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        home: home,
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
  await settle(tester);
}

/// Advances past transitions, snack bars and pending fake responses. The
/// Edge Function client decodes responses on the real event loop, so a short
/// real-time pause lets those arrive too.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> shot(WidgetTester tester, String path) =>
    expectLater(find.byKey(const Key('screen')), matchesGoldenFile(path));

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
