import 'package:flutter/material.dart';
import 'backend/services/supabase_service.dart';
import 'frontend/theme/app_theme.dart';
import 'frontend/auth/welcome_screen.dart';
import 'frontend/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  runApp(const MaakApp());
}

class MaakApp extends StatelessWidget {
  const MaakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Ma'ak",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SupabaseService.currentUser == null
          ? const WelcomeScreen()
          : const AuthGate(),
    );
  }
}
