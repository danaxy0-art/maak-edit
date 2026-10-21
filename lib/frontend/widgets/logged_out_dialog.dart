import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows the "You're logged out" confirmation modal from the mockups.
/// Call `showLoggedOutDialog(context)` right after SupabaseService.signOut().
Future<void> showLoggedOutDialog(
  BuildContext context, {
  required VoidCallback onBackToLogin,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.selectedCardFill,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, color: AppColors.primaryNavy),
            ),
            const SizedBox(height: 18),
            const Text(
              "You're logged out",
              style: TextStyle(
                fontFamily: 'MaakSerif',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You have been successfully logged out of your account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onBackToLogin,
                child: const Text('Back to login'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
