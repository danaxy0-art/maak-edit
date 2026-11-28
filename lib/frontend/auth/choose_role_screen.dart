import 'package:flutter/material.dart';
import '../redesign/ui.dart';
import '../redesign/registration.dart';
import '../theme/app_theme.dart';

class ChooseRoleScreen extends StatelessWidget {
  const ChooseRoleScreen({super.key});
  @override
  Widget build(BuildContext context) => AuthCanvas(
    anchored: true,
    heroTitle: 'Find your kind\nof support.',
    heroSubtitle: 'Choose the journey that feels right for you.',
    children: [
      const Text(
        'How can we be with you?',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Choose the journey that fits you.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted),
      ),
      const SizedBox(height: 24),
      _role(
        context,
        'Help seeker',
        'I’m living with a chronic condition and looking for peer support.',
        Icons.favorite_border,
        'help_seeker',
      ),
      const SizedBox(height: 14),
      _role(
        context,
        'Volunteer',
        'I have lived experience and want to support someone else.',
        Icons.people_outline,
        'volunteer',
      ),
    ],
  );
  Widget _role(
    BuildContext context,
    String title,
    String text,
    IconData icon,
    String role,
  ) => SurfaceCard(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RegistrationScreen(role: role)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 35, color: AppColors.primaryNavy),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: AppColors.textMuted, height: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward),
          ],
        ),
      ],
    ),
  );
}
