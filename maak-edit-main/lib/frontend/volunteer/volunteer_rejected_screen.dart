import 'package:flutter/material.dart';
import '../redesign/ui.dart';
import '../redesign/profile.dart';
import '../theme/app_theme.dart';
import '../widgets/maak_logo.dart';

class VolunteerRejectedScreen extends StatelessWidget {
  final String rejectionReason;
  const VolunteerRejectedScreen({super.key, required this.rejectionReason});
  @override
  Widget build(BuildContext context) => AuthCanvas(
    heroTitle: 'Your next step\nstarts here.',
    heroSubtitle: 'Update your details and continue your journey.',
    back: false,
    children: [
      const SizedBox(height: 15),
      const MaakLogo(iconSize: 36),
      const SizedBox(height: 50),
      Center(
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE5E5),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.error),
          ),
          child: const Icon(Icons.close, color: AppColors.error, size: 54),
        ),
      ),
      const SizedBox(height: 25),
      const Text(
        'Not approved',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'MaakSerif',
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: AppColors.error,
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Your application needs a few changes.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted),
      ),
      const SizedBox(height: 30),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reason for rejection',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              rejectionReason.isEmpty
                  ? 'Please contact the administrator for the reason.'
                  : rejectionReason,
              style: const TextStyle(color: AppColors.textMuted, height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 50),
      PrimaryButton(
        'Update and reapply',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const EditProfilePage(role: 'volunteer', reapply: true),
          ),
        ),
      ),
      TextButton(
        onPressed: () => logout(context),
        child: const Text('Log out'),
      ),
      const SizedBox(height: 100),
    ],
  );
}
