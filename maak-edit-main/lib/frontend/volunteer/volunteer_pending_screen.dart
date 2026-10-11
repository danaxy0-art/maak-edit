import 'package:flutter/material.dart';
import '../auth/auth_gate.dart';
import '../redesign/ui.dart';
import '../redesign/profile.dart';
import '../widgets/maak_logo.dart';
import '../theme/app_theme.dart';

class VolunteerPendingScreen extends StatelessWidget {
  const VolunteerPendingScreen({super.key});
  @override
  Widget build(BuildContext context) => AuthCanvas(
    heroTitle: 'Your experience\ncan make a difference.',
    heroSubtitle: 'Thank you for choosing to support someone.',
    back: false,
    children: [
      const SizedBox(height: 30),
      const MaakLogo(),
      const SizedBox(height: 50),
      const Icon(
        Icons.hourglass_empty,
        size: 70,
        color: AppColors.selectedCardBorder,
      ),
      const SizedBox(height: 24),
      const Text(
        'Your application is in review',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'MaakSerif',
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Thank you for sharing your experience. Our team will review your verification document and update your application status.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, height: 1.6),
      ),
      const SizedBox(height: 36),
      PrimaryButton(
        'Refresh status',
        icon: Icons.refresh,
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
        ),
      ),
      TextButton(
        onPressed: () => logout(context),
        child: const Text('Log out'),
      ),
    ],
  );
}
