import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maak_app/frontend/auth/choose_role_screen.dart';
import 'package:maak_app/frontend/auth/reset_password_screen.dart';
import 'package:maak_app/frontend/auth/verify_reset_otp_screen.dart';
import 'package:maak_app/frontend/volunteer/volunteer_pending_screen.dart';
import 'package:maak_app/frontend/redesign/home.dart';
import 'package:maak_app/frontend/redesign/profile.dart';
import 'package:maak_app/frontend/redesign/support.dart';
import 'package:maak_app/frontend/redesign/notifications.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/frontend/auth/welcome_screen.dart';
import 'package:maak_app/frontend/auth/login_screen.dart';
import 'package:maak_app/frontend/auth/new_password_screen.dart';
import 'package:maak_app/frontend/redesign/registration.dart';
import 'package:maak_app/frontend/redesign/admin.dart';
import 'package:maak_app/frontend/redesign/condition_field.dart';
import 'package:maak_app/frontend/volunteer/volunteer_rejected_screen.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var failConditions = false;
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('test/fonts/Roboto-Regular.ttf').readAsBytesSync(),
          ),
        ),
      );
    await loader.load();
    final serif = FontLoader('MaakSerif')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/DMSerifDisplay-Regular.ttf').readAsBytesSync(),
          ),
        ),
      );
    await serif.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('test/fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    await Supabase.initialize(
      httpClient: MockClient((request) async {
        if (failConditions &&
            request.url.path.endsWith('/chronic_conditions')) {
          return http.Response(
            jsonEncode({'message': 'missing table', 'code': '42P01'}),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        final data = request.url.path.endsWith('/chronic_conditions')
            ? [
                {
                  'id': '00000000-0000-0000-0000-000000000010',
                  'name': 'Diabetes',
                  'is_active': true,
                  'sort_order': 1,
                },
              ]
            : [];
        return http.Response(
          jsonEncode(data),
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
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
  });
  testWidgets(
    'failed conditions remain in Form validation and block submission',
    (tester) async {
      failConditions = true;
      final form = GlobalKey<FormState>();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Form(
                key: form,
                child: ConditionField(onChanged: (_) {}),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Reload conditions'), findsOneWidget);
        expect(form.currentState!.validate(), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        failConditions = false;
      }
    },
  );
  for (final role in ['volunteer', 'help_seeker']) {
    testWidgets('$role registers without a username input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: RegistrationScreen(role: role),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Username'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(4));
    });
  }
  tearDownAll(() async => Supabase.instance.dispose());
  final screens = <String, Widget>{
    'welcome': const WelcomeScreen(),
    'choose_role': const ChooseRoleScreen(),
    'reset_email': const ResetPasswordScreen(),
    'reset_otp': const VerifyResetOtpScreen(email: 'dana@example.com'),
    'signup_otp': const VerifySignupScreen(email: 'dana@example.com'),
    'pending': const VolunteerPendingScreen(),
    'home_seeker': const HomePage(role: 'help_seeker'),
    'home_volunteer': const HomePage(role: 'volunteer'),
    'profile': const ProfilePage(role: 'help_seeker'),
    'volunteers': const VolunteerDirectoryPage(),
    'requests': const RequestsPage(),
    'messages': const ConversationsPage(),
    'journey': const JourneyPage(),
    'schedule': const SchedulePage(),
    'book_session': const BookSessionPage(),
    'resources': const ResourcesPage(),
    'notifications': const NotificationsPage(),
    'admin_overview': AdminOverview(select: (_) {}),
    'admin_conditions': const ConditionsAdminPage(),
    'admin_applications': const ApplicationsPage(),
    'login': const LoginScreen(),
    'registration': const RegistrationScreen(role: 'help_seeker'),
    'password': const NewPasswordScreen(),
    'rejected': const VolunteerRejectedScreen(
      rejectionReason:
          'The uploaded verification document is unclear. Please upload a readable copy.',
    ),
    'reject_dialog': const Scaffold(
  body: RejectApplicationDialog(
    userId: '00000000-0000-0000-0000-000000000001',
    email: 'volunteer@example.com',
    name: 'Test Volunteer',
  ),
),
  };
  for (final entry in screens.entries) {
    testWidgets('${entry.key} renders at mobile size without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
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
            home: entry.value,
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/logo.png'),
          tester.element(find.byType(MaterialApp)),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/botanical_background.png'),
          tester.element(find.byType(MaterialApp)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('screen')),
        matchesGoldenFile('goldens/${entry.key}.png'),
      );
    });
  }
  testWidgets('login shows a clear error above email only after leaving it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('validation-preview'),
        child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/logo.png'),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'dana@');
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('validation-preview')),
      matchesGoldenFile('goldens/login_field_error.png'),
    );
  });
  testWidgets(
    'support preferences uses botanical hero and real selectable fields',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('preferences-preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const RegistrationScreen(role: 'help_seeker'),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/images/botanical_background.png'),
          tester.element(find.byType(MaterialApp)),
        );
        await precacheImage(
          const AssetImage('assets/images/logo.png'),
          tester.element(find.byType(MaterialApp)),
        );
      });
      expect(find.text('Username'), findsNothing);
      final values = ['Dana', 'dana@example.com', 'Dana123!', 'Dana123!'];
      for (var i = 0; i < values.length; i++) {
        final field = find.byType(TextField).at(i);
        await tester.ensureVisible(field);
        await tester.enterText(field, values[i]);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Select your condition'));
      await tester.tap(find.text('Select your condition'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diabetes'));
      await tester.pumpAndSettle();
      final languageField = find.byType(DropdownButton<String>);
      await tester.ensureVisible(languageField);
      await tester.pumpAndSettle();
      await tester.tap(languageField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      final scroll = find.byType(SingleChildScrollView).first;
      await tester.drag(scroll, const Offset(0, 1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Diabetes'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      await expectLater(
        find.byKey(const Key('preferences-preview')),
        matchesGoldenFile('goldens/support_preferences.png'),
      );
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Dana',
      );
    },
  );
  testWidgets('welcome remains usable with large text on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Create account'));
    expect(tester.takeException(), isNull);
  });
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}
