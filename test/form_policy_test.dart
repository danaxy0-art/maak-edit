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
  test('block reason matches admin_block_account: trimmed, 1-500', () {
    expect(validateBlockReason(null), 'Enter a reason for blocking this account');
    expect(validateBlockReason(' \n\t '), 'Enter a reason for blocking this account');
    expect(validateBlockReason('x'), isNull);
    expect(validateBlockReason('  ${'a' * 500}  '), isNull);
    expect(validateBlockReason('a' * 501), 'Use at most 500 characters');
  });
  test('reactivation note is optional but limited to 500', () {
    expect(validateReactivationNote(null), isNull);
    expect(validateReactivationNote(''), isNull);
    expect(validateReactivationNote('a' * 500), isNull);
    expect(validateReactivationNote('a' * 501), 'Use at most 500 characters');
  });
  test('appeal explanation matches submit_my_appeal: trimmed, 1-1000', () {
    const empty = 'Explain why your restriction should be reconsidered';
    expect(validateAppealMessage(null), empty);
    expect(validateAppealMessage(' \n\t '), empty);
    expect(validateAppealMessage('x'), isNull);
    expect(validateAppealMessage('  ${'a' * 1000}  '), isNull);
    expect(validateAppealMessage('a' * 1001), 'Use at most 1000 characters');
  });
  test('appeal decisions: rejection note required, approval note optional', () {
    expect(validateRejectionNote('  '), 'Explain why the appeal is rejected');
    expect(validateRejectionNote('a' * 1000), isNull);
    expect(validateRejectionNote('a' * 1001), 'Use at most 1000 characters');
    expect(validateApprovalNote(null), isNull);
    expect(validateApprovalNote(''), isNull);
    expect(validateApprovalNote('a' * 1001), 'Use at most 1000 characters');
  });
  test('rejection reason trims whitespace and enforces length', () {
    expect(validateReason('   '), 'Enter a rejection reason');
    expect(validateReason('a' * 500), isNull);
    expect(validateReason('a' * 501), isNotNull);
  });
}
