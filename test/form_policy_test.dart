import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/validation/form_policy.dart';

void main() {
  test('email validation rejects whitespace and missing domain', () {
    for (final email in [
      '',
      'dana@',
      'dana example.com',
      'dana@domain',
      'a @b.com',
    ]) {
      expect(validateEmail(email), isNotNull, reason: email);
    }
    expect(validateEmail(' dana@example.com '), isNull);
  });
  test('usernames have the same 3–30 character boundary as SQL', () {
    expect(validateUsername('ab'), isNotNull);
    expect(validateUsername('a' * 30), isNull);
    expect(validateUsername('a' * 31), isNotNull);
    expect(validateUsername('dana_x1'), isNull);
    expect(validateUsername('dana x1'), isNotNull);
  });
  test('confirmation never accepts an empty or different password', () {
    expect(validateConfirmation('', 'Dana123!'), isNotNull);
    expect(
      validateConfirmation('Dana123?', 'Dana123!'),
      'Passwords do not match',
    );
    expect(validateConfirmation('Dana123!', 'Dana123!'), isNull);
  });
  test('rejection reason trims whitespace and enforces length', () {
    expect(validateReason('   '), 'Enter a rejection reason');
    expect(validateReason('a' * 500), isNull);
    expect(validateReason('a' * 501), isNotNull);
  });
}
