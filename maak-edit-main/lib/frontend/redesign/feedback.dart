import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

String friendlyError(Object error) {
  if (error is AuthException) {
    final code = error.code;
    if (code == 'invalid_credentials') return 'Email or password is incorrect.';
    if (code == 'email_not_confirmed') {
      return 'Verify your email before logging in.';
    }
    if (code == 'user_already_exists') {
      return 'This email is already registered. Please log in.';
    }
    if (code == 'otp_expired') {
      return 'This code has expired. Request a new code.';
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit') {
      return 'Too many attempts. Please wait before trying again.';
    }
    return 'We could not verify your account. Check your details and try again.';
  }
  if (error is PostgrestException) {
    if (error.code == '23505') {
      return 'This username or record already exists. Choose another.';
    }
    if (error.code == '42501') {
      return 'You do not have permission to perform this action.';
    }
    if (error.message.contains('condition_inactive')) {
      return 'This condition is no longer available. Choose an active condition.';
    }
    if (error.message.contains('reason_required')) {
      return 'Enter a rejection reason.';
    }
    if (error.message.contains('application_changed')) {
      return 'This application has already been reviewed. Refresh the list.';
    }
    if (error.message.contains('invalid_username')) {
      return 'Use a username with 3–30 letters, numbers or underscores.';
    }
    if (error.code == '42P01' ||
        error.code == 'PGRST205' ||
        error.code == 'PGRST202' ||
        error.code == '42703' ||
        error.code == 'PGRST204' ||
        error.code == '42883') {
      return 'The database setup is incomplete. Please contact the administrator to finish setup.';
    }
    return 'Could not save or load data. Please retry. Error code: ${error.code ?? 'unknown'}.';
  }
  if (error is SocketException || error is TimeoutException) {
    return 'Check your internet connection and try again.';
  }
  if (error is StorageException) {
    return 'Could not upload or open the document. Please try again.';
  }
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Please check your details.';
  }
  return 'Something went wrong. Please try again.';
}

bool _errorDialogVisible = false;

void showAppError(
  BuildContext context,
  Object error, {
  VoidCallback? retry,
}) async {
  if (!context.mounted || _errorDialogVisible) return;
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  _errorDialogVisible = true;
  bool? retryRequested;
  try {
    retryRequested = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: AppColors.error, size: 36),
        title: const Text('Please check this'),
        content: Text(
          friendlyError(error),
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Close'),
          ),
          if (retry != null)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  } finally {
    _errorDialogVisible = false;
  }
  if (retryRequested == true && context.mounted) retry?.call();
}

void showSuccess(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
