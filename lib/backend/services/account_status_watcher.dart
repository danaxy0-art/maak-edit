import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../frontend/auth/blocked_account_screen.dart';
import 'push_notification_service.dart';
import 'supabase_service.dart';

/// Moves a member to the restricted-account (appeal) screen as soon as an
/// admin blocks them, while the app is open.
///
/// A blocked member can't read account_blocks or their notifications, so the
/// block is detected five ways:
///  * a Realtime broadcast the admin's app sends right after blocking
///    (SupabaseService.signalAccountStatusChange) - instant, no database setup,
///  * account_status_signals, streamed live (20261107030000): a trigger touches
///    the member's row the moment a block is added or removed,
///  * the "account restricted" push arriving while the app is in the foreground,
///  * the app coming back to the foreground,
///  * a light check every [interval] as a fallback.
class AccountStatusWatcher with WidgetsBindingObserver {
  AccountStatusWatcher._();
  static final _instance = AccountStatusWatcher._();

  static const interval = Duration(seconds: 3);

  /// How many restricted screens are mounted. A counter, not a flag: when one
  /// restricted screen replaces another ("Check again" while still blocked),
  /// the new one opens before the old one closes.
  static int _blockedScreens = 0;

  /// Set between pushing the restricted screen and its first build.
  static bool _redirecting = false;

  static bool get showingBlockedScreen => _blockedScreens > 0 || _redirecting;

  /// Called by BlockedAccountScreen's initState.
  static void blockedScreenOpened() {
    _blockedScreens++;
    _redirecting = false;
  }

  /// Called by BlockedAccountScreen's dispose.
  static void blockedScreenClosed() {
    if (_blockedScreens > 0) _blockedScreens--;
  }

  static bool _checking = false;
  static bool _started = false;
  static StreamSubscription<List<Map<String, dynamic>>>? _signal;
  static RealtimeChannel? _broadcast;
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
    final old = _broadcast;
    _broadcast = null;
    if (old != null) SupabaseService.client.removeChannel(old);
    _signalUser = me;
    if (me == null) return;
    // Instant nudge from the admin's app; the server check still decides.
    _broadcast = SupabaseService.client
        .channel(SupabaseService.accountStatusChannel(me))
        .onBroadcast(event: 'status', callback: (_) => checkNow())
        .subscribe();
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
      _redirecting = true;
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => BlockedAccountScreen(
            reason: block['reason'] as String? ?? '',
            blockedAt: block['blocked_at'] as String?,
          ),
        ),
        (_) => false,
      );
      // By the next frame the screen has registered itself (blockedScreenOpened).
      WidgetsBinding.instance.addPostFrameCallback((_) => _redirecting = false);
    } catch (error) {
      // Offline or a transient error: the next check will try again.
      _redirecting = false;
      debugPrint('Account status check failed: $error');
    } finally {
      _checking = false;
    }
  }
}
