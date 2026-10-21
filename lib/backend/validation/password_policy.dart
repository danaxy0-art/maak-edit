/// Shared validation for passwords created by the user.
String? validateNewPassword(String? value) {
  final password = value ?? '';
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
