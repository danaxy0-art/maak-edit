import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../redesign/ui.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'choose_role_screen.dart';
import 'auth_gate.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => AuthCanvas(
    back: false,
    heroHeight: 420,
    heroTitle: 'You’re not alone.',
    heroSubtitle:
        'A supportive community for people\nliving with chronic conditions.',
    children: [
      const Text(
        'Welcome to Ma’ak',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'MaakSerif', fontSize: 29),
      ),
      const SizedBox(height: 12),
      const Text(
        'Peer support, built around you.\nReal experiences. Genuine connections.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, height: 1.5),
      ),
      const SizedBox(height: 24),
      PrimaryButton(
        'Log in',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChooseRoleScreen()),
        ),
        child: const Text('Create account'),
      ),
      if (SupabaseService.currentUser != null)
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AuthGate()),
          ),
          child: const Text('Continue to my account'),
        ),
      const PrivacyNote(),
    ],
  );
}
