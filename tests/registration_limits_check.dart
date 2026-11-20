import '../lib/backend/validation/form_policy.dart';
import '../lib/backend/validation/password_policy.dart';

void expect(bool value, String label) {
  if (!value) throw StateError(label);
  print('PASS $label');
}

void main() {
  expect(validateName('A' * 30) == null, '30-character name accepted');
  expect(validateName('A' * 31) != null, '31-character name rejected');
  expect(validateName('س' * 30) == null, 'Arabic name boundary accepted');
  expect(
    validateEmail('${'a' * 242}@example.com') == null,
    '254-character email accepted',
  );
  expect(
    validateEmail('${'a' * 243}@example.com') != null,
    '255-character email rejected',
  );
  expect(
    validateNewPassword('A1!${'x' * 69}') == null,
    '72-byte password accepted',
  );
  expect(
    validateNewPassword('A1!${'x' * 70}') != null,
    '73-byte password rejected',
  );
  expect(
    validateNewPassword('A1!${'س' * 35}') != null,
    'multibyte password length checked',
  );
  expect(
    validateReason('a' * 500) == null && validateReason('a' * 501) != null,
    'rejection reason boundary',
  );
}
