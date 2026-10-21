import '../redesign/app_text_field.dart';
import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../redesign/ui.dart';
import '../redesign/feedback.dart';
import '../widgets/maak_logo.dart';
import '../theme/app_theme.dart';
import 'verify_reset_otp_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.sendPasswordReset(_email.text);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyResetOtpScreen(email: _email.text.trim()),
          ),
        );
      }
    } catch (e) {
      if (mounted) showAppError(context, e, retry: _send);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthCanvas(
    heroTitle: 'A fresh start.\nA safe connection.',
    heroSubtitle: 'We’ll help you get back to your community.',
    children: [
      const MaakLogo(),
      const SizedBox(height: 35),
      const Text(
        'Reset your password',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'MaakSerif',
          fontSize: 27,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Enter your email address and we’ll send you a verification code.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, height: 1.5),
      ),
      const SizedBox(height: 22),
      Form(
        key: _form,
        autovalidateMode: AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Email address', requiredField: true),
            AppTextField(
              controller: _email,
              validator: validateEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              'Send verification code',
              busy: _busy,
              onPressed: _send,
            ),
          ],
        ),
      ),
    ],
  );
}
