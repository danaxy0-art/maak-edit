import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/backend/services/supabase_service.dart';
import 'package:maak_app/frontend/redesign/profile.dart';
import 'package:maak_app/frontend/redesign/multi_condition_field.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

class _PkceStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var optionalMissing = false, detailMissing = false, baseMissing = false;
  var repaired = false;
  const id = '10000000-0000-0000-0000-000000000001';
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
        final path = request.url.path;
        Object? data;
        var status = 200;
        if (path.endsWith('/token')) {
          final payload = base64Url
              .encode(utf8.encode(jsonEncode({'sub': id, 'exp': 4102444800})))
              .replaceAll('=', '');
          data = {
            'access_token': 'e30.$payload.signature',
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': id,
              'aud': 'authenticated',
              'email': 'dana@example.com',
              'created_at': '2026-10-20T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {'full_name': 'Dana'},
            },
          };
        } else if (path.endsWith('/ensure_maak_profile')) {
          repaired = true;
          baseMissing = false;
          data = 'help_seeker';
        } else if (path.endsWith('/profiles')) {
          final row = {
            'full_name': 'Dana',
            'username': 'dana',
            'role': 'help_seeker',
          };
          data = baseMissing
              ? []
              : (request.headers['accept']?.contains('vnd.pgrst.object') == true
                    ? row
                    : [row]);
        } else if (path.endsWith('/help_seeker_profiles')) {
          data = detailMissing
              ? []
              : [
                  {
                    'user_id': id,
                    'chronic_condition': 'Diabetes',
                    'preferred_language': 'English',
                    'description': 'Support',
                  },
                ];
        } else if (path.endsWith('/my_maak_conditions')) {
          data = optionalMissing
              ? {'code': 'PGRST202', 'message': 'Function missing'}
              : [
                  {'name': 'Diabetes', 'id': 'disease-1', 'is_active': true},
                ];
          if (optionalMissing) status = 404;
        } else if (path.endsWith('/condition_review_requests')) {
          data = optionalMissing
              ? {'code': 'PGRST205', 'message': 'Table missing'}
              : [];
          if (optionalMissing) status = 404;
        } else if (path.endsWith('/chronic_conditions')) {
          data = [
            {
              'id': 'disease-1',
              'name': 'Diabetes',
              'is_active': true,
              'aliases': ['سكر'],
            },
            {
              'id': 'other',
              'name': 'Other',
              'is_active': true,
              'is_other': true,
              'aliases': [],
            },
          ];
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
      email: 'dana@example.com',
      password: 'Test123!',
    );
  });
  setUp(() {
    optionalMissing = false;
    detailMissing = false;
    baseMissing = false;
    repaired = false;
  });
  tearDownAll(() => Supabase.instance.dispose());

  test(
    'legacy profile loads when optional condition setup is absent',
    () async {
      optionalMissing = true;
      final profile = await SupabaseService.loadProfileForEdit(
        role: 'help_seeker',
      );
      expect(profile['full_name'], 'Dana');
      expect(profile['conditions'], ['Diabetes']);
      expect(profile['setup_incomplete'], true);
    },
  );
  test('missing base profile uses authenticated repair', () async {
    baseMissing = true;
    final profile = await SupabaseService.loadProfileForEdit(
      role: 'help_seeker',
    );
    expect(repaired, true);
    expect(profile['full_name'], 'Dana');
  });
  testWidgets('phone profile renders name, email and current condition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ProfilePage(role: 'help_seeker'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dana'), findsOneWidget);
    expect(find.text('dana@example.com'), findsOneWidget);
    expect(find.text('Diabetes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('incomplete detail offers completion on phone', (tester) async {
    detailMissing = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ProfilePage(role: 'help_seeker'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Complete my profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Other has blur validation and Arabic canonical suggestions', (
    tester,
  ) async {
    final text = TextEditingController();
    var values = ['Other'];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              child: StatefulBuilder(
                builder: (context, update) => MultiConditionField(
                  values: values,
                  otherController: text,
                  onChanged: (next) => update(() => values = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter 3–60 characters.'), findsNothing);
    await tester.enterText(find.byType(TextField), 'سكر');
    await tester.pumpAndSettle();
    expect(find.text('Choose this existing condition'), findsOneWidget);
    await tester.tap(find.text('Choose this existing condition'));
    await tester.pumpAndSettle();
    expect(values, ['Diabetes']);
    expect(text.text, '');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    text.dispose();
  });
}
