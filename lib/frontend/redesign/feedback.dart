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
      return 'This record already exists. For conditions, choose the existing name or link the request to it.';
    }
    if (error.code == '42501') {
      return 'You do not have permission to perform this action.';
    }
    if (error.message.contains('invalid_other_name'))
      return 'Enter a condition name of 3–60 characters, without links or numbers only.';
    if (error.message.contains('condition_already_listed'))
      return 'This condition is already listed. Select the existing condition.';
    if (error.message.contains('request_changed'))
      return 'This request has already changed. Refresh the list.';
    if (error.message.contains('role_not_allowed'))
      return 'Your account role does not match this profile. Sign out and log in again.';
    final moderation = _moderationMessage(error.message);
    if (moderation != null) return moderation;
    if (error.message.contains('not_allowed'))
      return 'Sign in with an account permitted to perform this action.';
    if (error.message.contains('invalid_conditions'))
      return 'Select between 1 and 20 conditions.';
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

// Error codes raised by 20261021_account_blocking.sql. Checked before the
// generic 'not_allowed' message, which none of these codes contain.
const _moderationMessages = {
  'account_blocked':
      "This account has been blocked. Sign out, or contact the Ma'ak team if you think this is a mistake.",
  'participant_unavailable':
      'This person is not available right now. Choose another volunteer or try again later.',
  'request_participants_immutable':
      'This support request can no longer be changed. Refresh and try again.',
  'request_link_immutable':
      'This conversation can no longer be changed. Refresh and try again.',
  'invalid_block_reason': 'Enter a reason of at most 500 characters.',
  'cannot_block_self': 'You cannot block your own account.',
  'cannot_block_admin': 'Administrator accounts cannot be blocked.',
  'already_blocked': 'This account is already blocked. Refresh the list.',
  'not_blocked': 'This account is already active. Refresh the list.',
  'account_not_found': 'This account no longer exists. Refresh the list.',
  // Appeals (20261023_account_appeals.sql).
  'account_active':
      'This account is no longer restricted. Tap Check again to continue.',
  'appeal_pending':
      'An appeal is already being reviewed. Wait for an administrator to respond.',
  'appeal_limit_reached': 'All 3 appeals for this restriction have been used.',
  'invalid_appeal_message': 'Enter an explanation of at most 1000 characters.',
  'appeal_not_found': 'This appeal no longer exists. Refresh the list.',
  'appeal_already_decided':
      'Another administrator has already reviewed this appeal. Refresh the list.',
  'appeal_not_current':
      'This appeal belongs to an earlier restriction. Refresh the list.',
  'invalid_decision_note': 'Enter a note of at most 1000 characters.',
};

String? _moderationMessage(String message) {
  for (final entry in _moderationMessages.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  return null;
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
