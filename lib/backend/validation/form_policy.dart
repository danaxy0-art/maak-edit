const usernameLimit = 30;
const fullNameLimit = 30;

String? validateName(String? value) {
  final v = value?.trim() ?? '';

  if (v.isEmpty) {
    return 'Enter your full name';
  }

  if (v.length < 2) {
    return 'Use at least 2 characters';
  }

  if (v.length > fullNameLimit) {
    return 'Use at most 30 characters';
  }

  // Supports Arabic and English names, spaces, hyphens, and apostrophes.
  if (!RegExp(r"^[a-zA-Z\u0600-\u06FF\s'-]+$").hasMatch(v)) {
    return 'Use letters only';
  }

  return null;
}

String? validateEmail(String? value) {
  final v = value?.trim() ?? '';

  if (v.isEmpty) {
    return 'Enter your email address';
  }

  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
    return 'Enter a valid email address';
  }

  return null;
}

String? validateUsername(String? value) {
  final v = value?.trim() ?? '';

  if (v.isEmpty) {
    return 'Enter a username';
  }

  if (v.length < 3 || v.length > usernameLimit) {
    return 'Use 3–30 characters';
  }

  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
    return 'Use letters, numbers and underscores only';
  }

  return null;
}

String? validateConfirmation(String? value, String password) {
  if (value == null || value.isEmpty) {
    return 'Re-enter your password';
  }

  if (value != password) {
    return 'Passwords do not match';
  }

  return null;
}

String? validateReason(String? value) {
  final v = value?.trim() ?? '';

  if (v.isEmpty) {
    return 'Enter a rejection reason';
  }

  if (v.length > 500) {
    return 'Use at most 500 characters';
  }

  return null;
}
