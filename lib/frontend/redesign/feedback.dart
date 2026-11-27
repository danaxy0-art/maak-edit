import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../design/components.dart';
import '../design/tokens.dart';

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
    if (error.message.contains('ai_matching_disabled')) {
      return 'Activate AI matching in your profile to find a match.';
    }
    if (error.message.contains('volunteer_matching_disabled')) {
      return 'This volunteer is not available for new matches. Please choose another volunteer.';
    }
    if (error.message.contains('sender_only')) {
      return 'You can delete only your own messages for everyone.';
    }
    if (error.message.contains('message_unavailable')) {
      return 'This message is no longer available. Refresh the conversation.';
    }
    if (error.code == '23505') {
      return 'This record already exists. For conditions, choose the existing name or link the request to it.';
    }
    if (error.code == '42501') {
      return 'You do not have permission to perform this action.';
    }
    if (error.message.contains('invalid_other_name')) {
      return 'Enter a condition name of 3–60 characters, without links or numbers only.';
    }
    if (error.message.contains('condition_already_listed')) {
      return 'This condition is already listed. Select the existing condition.';
    }
    if (error.message.contains('request_changed')) {
      return 'This request has already changed. Refresh the list.';
    }
    if (error.message.contains('role_not_allowed')) {
      return 'Your account role does not match this profile. Sign out and log in again.';
    }
       
             // === ADDED: report errors ===
    if (error.message.contains('already_reported')) {
      return 'You already reported this message.';
    }
    if (error.message.contains('cannot_report_own_message')) {
      return 'You cannot report your own message.';
    }
    // === ADDED (new): reporting a deleted message ===
    if (error.message.contains('message_deleted')) {
      return 'This message was deleted, so it can no longer be reported.';
    }
    // === END ADDED (new) ===
    if (error.message.contains('invalid_report_reason')) {
      return 'Choose a reason for your report.';
    }
    if (error.message.contains('invalid_report_description')) {
      return 'Keep the description under 500 characters.';
    }
    // === END ADDED ===
    final moderation = _moderationMessage(error.message);
    if (moderation != null) return moderation;
    // === ADDED BY RAZAN: session scheduling errors ===
        if (error.message.contains('invalid_slot_time')) {
      return 'Choose a future time, at most 90 days ahead, lasting 15 minutes to 4 hours.';
    }
        if (error.message.contains('slot_overlap')) {
      return 'You already have a time slot that overlaps this one.';
    }
        if (error.message.contains('slot_limit')) {
      return 'You can keep up to 50 upcoming time slots. Remove one first.';
    }
        if (error.message.contains('slot_booked')) {
      return 'Someone has requested this time. Respond to the session request first.';
    }
        if (error.message.contains('slot_unavailable')) {
      return 'This time is no longer available. Choose another time.';
    }
        if (error.message.contains('session_overlap')) {
      return 'You already have a session at this time.';
    }
        if (error.message.contains('too_many_pending')) {
      return 'You can have up to 3 session requests waiting for an answer.';
    }
        if (error.message.contains('session_changed')) {
      return 'This session has already changed. Refresh the list.';
    }
        if (error.message.contains('session_started')) {
      return 'This session has already started, so it cannot be changed.';
    }
        if (error.message.contains('reschedule_limit')) {
      return 'A session can be rescheduled up to 3 times.';
    }
    // === END ADDED BY RAZAN ===
    // === Health Library articles and comments (20261126000000) ===
    final article = _articleMessage(error.message);
    if (article != null) return article;
    if (error.message.contains('not_allowed')) {
      return 'Sign in with an account permitted to perform this action.';
    }
    if (error.message.contains('invalid_conditions')) {
      return 'Select between 1 and 20 conditions.';
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
  // Admin report management (20261106100000_admin_report_management.sql).
  'report_already_decided':
      'Another administrator has already decided this report. Refresh to see the latest status.',
  'report_not_found': 'This report no longer exists. Refresh the list.',
  'invalid_report_decision_note': 'Enter a reason of at most 500 characters.',
  'invalid_report_status': 'Choose a valid report status.',
  'conversation_already_restricted':
      'An administrator has already ended this conversation. You can dismiss the report instead.',
  'conversation_unavailable':
      'This conversation is no longer available. You can dismiss the report instead.',
  'conversation_changed':
      'This conversation has already changed. Refresh and try again.',
  // Lift restriction (20261107110000_admin_lift_restriction.sql).
  'conversation_not_restricted':
      'This restriction has already been lifted. Refresh to see the latest status.',
  'invalid_lift_reason': 'Enter a reason of at most 500 characters.',
  // Appeal cooldown (20261107120000_appeal_cooldown.sql).
  'appeal_cooldown':
      'You can appeal again after the 90-day waiting period. Tap Check again to see the date.',
  'appeal_attempt_invalid':
      'Your appeal status has changed. Tap Check again and try once more.',
};

// Error codes raised by 20261126000000_article_management_comments.sql.
// Checked before the generic 'not_allowed' message.
const _articleMessages = {
  // 20261127010000_member_profiles.sql
  'profile_unavailable': 'This profile is not available.',
  'comment_not_allowed':
      'Only help seekers and approved volunteers can comment on articles.',
  'comment_rate_limited':
      'You are commenting very quickly. Please wait a minute and try again.',
  'invalid_comment': 'Write a comment of 1 to 1000 characters.',
  'comment_unavailable':
      'This comment is no longer available. Refresh the comments.',
  'article_unavailable':
      'This article is no longer available. Refresh the list.',
  'invalid_article_title': 'Enter a title of 3 to 200 characters.',
  'invalid_article_summary': 'Enter a summary of 10 to 500 characters.',
  'invalid_article_content': 'Enter article content of 20 to 20,000 characters.',
  'invalid_article_source': 'Keep the source name under 120 characters.',
  'invalid_article_url':
      'Enter a valid source link that starts with https:// or http://.',
  'invalid_article_image': 'Enter a valid image link that starts with https://.',
  'invalid_article_status': 'Choose Draft or Published.',
  'article_source_required':
      'Add a source name and link before publishing this article.',
  'invalid_article_condition':
      'This health condition is no longer available. Choose another one.',
};

String? _articleMessage(String message) {
  for (final entry in _articleMessages.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  return null;
}

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
        actionsAlignment: MainAxisAlignment.center,
        icon: const IconBadge(
          Icons.error_outline,
          size: 56,
          color: Color(0xFFFDE8E8),
        ),
        title: const Text('Please check this'),
        content: Text(
          friendlyError(error),
          style: MaakText.body.copyWith(
            fontSize: 16,
            height: 1.5,
            color: MaakColors.ink,
          ),
        ),
        actionsOverflowButtonSpacing: MaakSpace.sm,
        actions: [
          if (retry != null)
            PillButton(
              'Close',
              outlined: true,
              onPressed: () => Navigator.pop(dialogContext, false),
            )
          else
            PillButton(
              'Close',
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          if (retry != null)
            PillButton(
              'Try again',
              onPressed: () => Navigator.pop(dialogContext, true),
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
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: MaakColors.orbBlush,
                size: 20,
              ),
              const SizedBox(width: MaakSpace.md),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
