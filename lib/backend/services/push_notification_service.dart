import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../frontend/auth/auth_gate.dart';
import 'supabase_service.dart';

/// Firebase Cloud Messaging for Ma'ak.
///
/// The server sends the pushes (see supabase/functions/send-push). This class:
///  * registers the device token with Supabase whenever someone is signed in,
///    and removes it on sign-out so the next user doesn't get their pushes;
///  * routes a tapped notification to the right screen.
class PushNotificationService {
  PushNotificationService._();

  /// Root navigator of the app (set on MaterialApp).
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// A tapped chat/request notification waiting for AppShell to open it.
  /// Holds the same shape as a notifications row: id, kind, reference_id.
  static final pendingOpen = ValueNotifier<Map<String, dynamic>?>(null);

  /// An admin tab a tapped push asks AdminShell to open (4 = Appeals).
  static final pendingAdminTab = ValueNotifier<int?>(null);

  /// Kinds that change which top-level screen the user should see.
  static const _rerouteKinds = {'application', 'account', 'account_blocked'};

  static String? _savedToken;
  static bool _started = false;

  static Future<void> init() async {
    if (_started) return;
    _started = true;
    final messaging = FirebaseMessaging.instance;

    // Already signed in from a previous launch.
    if (SupabaseService.currentUser != null) unawaited(_register());
    SupabaseService.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn && state.session != null) {
        unawaited(_register());
      }
    });

    messaging.onTokenRefresh.listen((token) {
      if (SupabaseService.currentUser != null) unawaited(_save(token));
    });

    // Tap while the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // Tap that launched the app from a closed state.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);
  }

  /// Takes the pending tapped notification (if any) so it opens only once.
  static Map<String, dynamic>? takePendingOpen() {
    final value = pendingOpen.value;
    pendingOpen.value = null;
    return value;
  }

  /// Call before signing out, while the session is still valid.
  static Future<void> forgetDevice() async {
    final token = _savedToken;
    _savedToken = null;
    pendingOpen.value = null;
    if (token == null) return;
    try {
      await SupabaseService.client.rpc(
        'unregister_maak_device_token',
        params: {'p_token': token},
      );
    } catch (e) {
      debugPrint('Push: could not remove device token: $e');
    }
  }

  static Future<void> _register() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token != null) await _save(token);
    } catch (e) {
      // Push is optional; never break sign-in over it.
      debugPrint('Push: registration failed: $e');
    }
  }

  static Future<void> _save(String token) async {
    try {
      await SupabaseService.client.rpc(
        'register_maak_device_token',
        params: {'p_token': token, 'p_platform': _platform},
      );
      _savedToken = token;
    } catch (e) {
      debugPrint('Push: could not save device token: $e');
    }
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  static void _handleTap(RemoteMessage message) {
    final kind = message.data['kind'] as String?;
    if (kind == null || SupabaseService.currentUser == null) return;

    if (kind == 'appeal') {
      // Admin: AdminShell opens its Appeals tab (now if it's showing, or as
      // soon as it loads).
      pendingAdminTab.value = 4;
      return;
    }

    if (_rerouteKinds.contains(kind)) {
      // Application decision, restriction or reactivation: rebuild from
      // AuthGate so the user lands on their up-to-date screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      });
      return;
    }

    // Chat, request and match taps are opened by AppShell, which owns those screens.
    pendingOpen.value = {
      'id': message.data['id'],
      'kind': kind,
      'reference_id': message.data['reference_id'],
    };
  }
}
