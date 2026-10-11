import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../redesign/ui.dart';
import '../redesign/feedback.dart';
import '../redesign/password_fields.dart';
import 'login_screen.dart';

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _busy = false, _saved = false;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _finish({bool save = false}) async {
    if (_busy || (save && !_form.currentState!.validate())) return;
    setState(() => _busy = true);
    try {
      if (save && !_saved) {
        await SupabaseService.setRecoveredPassword(_password.text);
        _saved = true;
      }
      await SupabaseService.endPasswordRecovery();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      if (_saved) {
        showSuccess(
          context,
          'Password updated. Log in with your new password.',
        );
      }
    } catch (e) {
      if (mounted) showAppError(context, e, retry: () => _finish(save: save));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_busy) _finish();
    },
    child: AuthCanvas(
      heroTitle: 'A fresh start.\nA safe connection.',
      heroSubtitle: 'Choose a new password for your account.',
      children: [
        const Text(
          'Reset your password',
          style: TextStyle(fontFamily: 'MaakSerif', fontSize: 27),
        ),
        const SizedBox(height: 14),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordFields(
                password: _password,
                confirmation: _confirmation,
                enabled: !_busy && !_saved,
                label: 'New password',
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                _saved ? 'Return to login' : 'Save password',
                busy: _busy,
                onPressed: () => _finish(save: true),
              ),
              const PrivacyNote(),
            ],
          ),
        ),
      ],
    ),
  );
}
