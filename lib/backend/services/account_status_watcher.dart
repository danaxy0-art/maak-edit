import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../frontend/auth/blocked_account_screen.dart';
import 'push_notification_service.dart';
import 'supabase_service.dart';

/// Moves a member to the restricted-account (appeal) screen as soon as an
/// admin blocks them, while the app is open.
///
/// A blocked member can't read account_blocks or their notifications, so the
/// block is detected four ways:
///  * account_status_signals, streamed live (20261107030000): a trigger touches
///    the member's row the moment a block is added or removed,
///  * the "account restricted" push arriving while the app is in the foreground,
///  * the app coming back to the foreground,
///  * a light check every [interval] as a fallback.
class AccountStatusWatcher with WidgetsBindingObserver {
  AccountStatusWatcher._();
  static final _instance = AccountStatusWatcher._();

  static const interval = Duration(seconds: 5);

  /// Set by BlockedAccountScreen while it is on screen, so it isn't re-opened.
  static bool showingBlockedScreen = false;

  static bool _checking = false;
  static bool _started = false;
  static StreamSubscription<List<Map<String, dynamic>>>? _signal;
  static String? _signalUser;

  static void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_instance);
    // Runs for the app's lifetime; skipped cheaply while signed out.
    Timer.periodic(interval, (_) => checkNow());
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['kind'] == 'account_blocked') checkNow();
    });
    _watchSignal();
    SupabaseService.client.auth.onAuthStateChange.listen((_) => _watchSignal());
  }

  // Follows the signed-in user's status signal; re-subscribes on sign-in/out.
  static void _watchSignal() {
    final me = SupabaseService.currentUser?.id;
    if (me == _signalUser) return;
    _signal?.cancel();
    _signal = null;
    _signalUser = me;
    if (me == null) return;
    _signal = SupabaseService.client
        .from('account_status_signals')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', me)
        .listen(
          (_) => checkNow(),
          // Not installed yet, or the connection dropped: the timer still runs.
          onError: (Object error) =>
              debugPrint('Account status stream unavailable: $error'),
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkNow();
  }

  static Future<void> checkNow() async {
    if (_checking ||
        showingBlockedScreen ||
        SupabaseService.currentUser == null) {
      return;
    }
    _checking = true;
    try {
      final block = await SupabaseService.getMyBlockStatus();
      if (block == null || showingBlockedScreen) return;
      final nav = PushNotificationService.navigatorKey.currentState;
      if (nav == null) return;
      showingBlockedScreen = true;
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => BlockedAccountScreen(
            reason: block['reason'] as String? ?? '',
            blockedAt: block['blocked_at'] as String?,
          ),
        ),
        (_) => false,
      );
    } catch (_) {
      // Offline or a transient error: the next check will try again.
    } finally {
      _checking = false;
    }
  }
}
