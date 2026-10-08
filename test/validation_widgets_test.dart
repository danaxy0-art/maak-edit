import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/redesign/password_fields.dart';
import 'package:maak_app/frontend/redesign/app_text_field.dart';
import 'package:maak_app/frontend/redesign/feedback.dart';
import 'package:maak_app/backend/validation/form_policy.dart';
import 'package:maak_app/frontend/redesign/admin.dart';
import 'package:maak_app/frontend/theme/app_theme.dart';

void main() {
  testWidgets(
    'password mismatch waits for blur and is rechecked on submission',
    (tester) async {
      final password = TextEditingController(),
          confirmation = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                child: PasswordFields(
                  password: password,
                  confirmation: confirmation,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Dana123!');
      await tester.enterText(find.byType(TextField).last, 'Dana123?');
      await tester.pump();
      expect(find.text('Passwords do not match'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Dana123!');
      await tester.pump();
      expect(find.text('Passwords match'), findsOneWidget);
      password.text = 'Dana456!';
      Form.of(tester.element(find.byType(PasswordFields))).validate();
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(find.text('Passwords match'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      password.dispose();
      confirmation.dispose();
    },
  );
  testWidgets(
    'email errors wait for blur and never validate untouched password',
    (tester) async {
      final email = TextEditingController(), password = TextEditingController();
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Form(
              key: form,
              child: Column(
                children: [
                  AppTextField(controller: email, validator: validateEmail),
                  AppTextField(
                    controller: password,
                    validator: (v) => v!.isEmpty ? 'Enter password' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(find.byType(FieldErrorNotice), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'invalid');
      await tester.pump();
      expect(find.byType(FieldErrorNotice), findsNothing);
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Enter password'), findsNothing);
      final notice = tester.getTopLeft(find.byType(FieldErrorNotice));
      final input = tester.getTopLeft(find.byType(TextField).first);
      expect(notice.dy, lessThan(input.dy));
      form.currentState!.validate();
      await tester.pump();
      expect(find.text('Enter password'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      email.dispose();
      password.dispose();
    },
  );
  testWidgets('service errors appear in a dialog with retry and no snackbar', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppError(
                context,
                ArgumentError('Check connection'),
                retry: () => retried = true,
              ),
              child: const Text('Trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('missing rejection reason stays visible inside dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: RejectApplicationDialog(
  userId: '00000000-0000-0000-0000-000000000001',
  email: 'volunteer@example.com',
  name: 'Test Volunteer',
),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pump();
    expect(find.text('Enter a rejection reason'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
