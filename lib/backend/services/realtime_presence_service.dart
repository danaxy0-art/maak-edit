import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimePresenceService with WidgetsBindingObserver {
  static final instance = RealtimePresenceService._();

  RealtimePresenceService._();

  final _supabase = Supabase.instance.client;

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSubscription;

  bool _initialized = false;
  bool _foreground = false;
  String? _userId;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    _foreground = WidgetsBinding.instance.lifecycleState ==
        AppLifecycleState.resumed;

    _authSubscription =
        _supabase.auth.onAuthStateChange.listen((data) {
          _syncPresence();
        });

    _syncPresence();
  }

  Future<void> _syncPresence() async {    final user = _supabase.auth.currentUser;
    debugPrint('SERVICE USER ID: ${user?.id}');
    debugPrint('SERVICE ROLE: ${user?.role}');
    debugPrint('FOREGROUND: $_foreground');

    if (!_foreground || user == null) {
      _disconnect();
      return;
    }

    if (_channel != null && _userId == user.id) return;

    _disconnect();

    _userId = user.id;
  await _supabase.realtime.setAuth(
    _supabase.auth.currentSession?.accessToken,
  );
    final channel = _supabase.channel(
      'presence:${user.id}',
      opts: const RealtimeChannelConfig(private: true),
    );

    _channel = channel;

    channel.subscribe((status, error) async {
      if (_channel != channel) return;

      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await channel.track({
            'online': true,
          });

          debugPrint('Realtime Presence: Online');
        } catch (e) {
          debugPrint('Presence tracking failed: $e');
        }
      } else {
        debugPrint('Presence status for ${user.id}: $status - $error');      }
    });
  }

  void _disconnect() {
    final channel = _channel;

    _channel = null;
    _userId = null;

    if (channel != null) {
      _supabase.removeChannel(channel);
      debugPrint('Realtime Presence: Disconnected');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPresence();
  }

  void dispose() {
    _disconnect();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _initialized = false;
  }
}