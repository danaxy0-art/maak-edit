import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/validation/password_policy.dart';

void main() {
  test('rejects passwords shorter than eight characters', () {
    expect(validateNewPassword('Ab1!xyz'), isNotNull);
  });
  test('requires an uppercase letter, number, and symbol', () {
    for (final value in ['abcdef1!', 'Abcdefg!', 'Abcdef12', 'Abcdef1 ']) {
      expect(validateNewPassword(value), isNotNull, reason: value);
    }
  });
  test('accepts valid passwords at the eight character boundary', () {
    expect(validateNewPassword('Abcdef1!'), isNull);
    expect(validateNewPassword('MYpass2026@'), isNull);
  });
  test('rejects missing password', () {
    expect(validateNewPassword(null), isNotNull);
    expect(validateNewPassword(''), isNotNull);
  });
}
