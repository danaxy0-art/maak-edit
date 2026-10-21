import '../redesign/app_text_field.dart';
import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../redesign/ui.dart';
import '../redesign/feedback.dart';
import '../theme/app_theme.dart';
import 'auth_gate.dart';
import 'reset_password_screen.dart';
import 'choose_role_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _hidden = true, _busy = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.signIn(
        email: _email.text,
        password: _password.text,
      );
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) showAppError(context, e, retry: _login);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthCanvas(
    heroHeight: 365,
    children: [
      const Text(
        'Welcome back',
        style: TextStyle(fontFamily: 'MaakSerif', fontSize: 29, height: 1.1),
      ),
      const SizedBox(height: 6),
      const Text(
        'Glad to see you again.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 15),
      ),
      const SizedBox(height: 22),
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _email,
              validator: validateEmail,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _password,
              obscureText: _hidden,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Enter your password' : null,
              autofillHints: const [AutofillHints.password],
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ResetPasswordScreen(),
                        ),
                      ),
                child: const Text('Forgot your password?'),
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton('Log in', busy: _busy, onPressed: _login),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('or'),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChooseRoleScreen(),
                      ),
                    ),
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    ],
  );
}
