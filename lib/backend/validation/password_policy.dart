import 'dart:convert';

/// Shared validation for passwords created by the user.
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (utf8.encode(password).length > 72)
    return 'Password is too long. Shorten it; some characters take extra space.';
  if (password.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Include an uppercase letter';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) return 'Include a number';
  if (!RegExp(r'[^a-zA-Z0-9\s]').hasMatch(password)) {
    return 'Include a symbol (such as ! or @)';
  }
  return null;
}
