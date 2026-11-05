import '../lib/backend/validation/form_policy.dart';

void main() {
  for (final input in [
    'User@Example.COM',
    'user@example.com',
    ' USER@example.com ',
  ]) {
    if (normalizeEmail(input) != 'user@example.com')
      throw StateError('Email case mismatch');
  }
  if (normalizeEmail('First.Last+Tag@Example.com') !=
      'first.last+tag@example.com')
    throw StateError('Address structure changed');
  print(
    'PASS email casing, surrounding spaces, and preserved address structure',
  );
}
