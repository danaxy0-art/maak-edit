import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend/services/account_status_watcher.dart';
import 'backend/services/chat_alert_service.dart';
import 'backend/services/device_session_reminders.dart';
import 'backend/services/push_notification_service.dart';
import 'backend/services/supabase_service.dart';
import 'backend/services/realtime_presence_service.dart';
import 'firebase_options.dart';
import 'frontend/calls/voice_calls.dart';
import 'frontend/auth/auth_gate.dart';
import 'frontend/auth/welcome_screen.dart';
import 'frontend/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Sprint 4 US6: pushes received while the app is closed or in the
  // background. Firebase allows one such handler for the whole app; add any
  // other background work to it rather than registering a second one.
  if (sessionRemindersSupported) {
    FirebaseMessaging.onBackgroundMessage(sessionRemindersOnBackgroundMessage);
  }
  await SupabaseService.init();

  // Dark status bar icons on every screen (see AppTheme.systemBars).
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemBars);

  runApp(const MaakApp());

  // After runApp so the permission prompt doesn't delay the first frame.
  PushNotificationService.init();
  // New chat message alerts: Supabase Realtime + local notifications (no FCM).
  // Sprint 4 US6: reminders before confirmed sessions, scheduled on the phone.
  // Started after the chat alerts, which initialise the notification plugin.
  ChatAlertService.init().whenComplete(AppSessionReminders.init);
  // Sends a member to the restricted screen as soon as an admin blocks them.
  AccountStatusWatcher.start();

  // Realtime online/offline presence.
  RealtimePresenceService.instance.initialize();
}

class MaakApp extends StatelessWidget {
  const MaakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Ma'ak",
      // Re-applies the status bar style on every screen, including screens
      // without an AppBar and after returning from other apps.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars,
        child: VoiceCallHost(child: child ?? const SizedBox.shrink()),
      ),
      debugShowCheckedModeBanner: false,
      navigatorKey: PushNotificationService.navigatorKey,
      theme: AppTheme.light(),
      home: SupabaseService.currentUser == null
          ? const WelcomeScreen()
          : const AuthGate(),
    );
  }
}