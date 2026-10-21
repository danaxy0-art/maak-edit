import '../redesign/app_text_field.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../backend/services/supabase_service.dart';
import '../redesign/feedback.dart';
import '../redesign/ui.dart';
import 'new_password_screen.dart';

class VerifyResetOtpScreen extends StatefulWidget {
  final String email;
  const VerifyResetOtpScreen({super.key, required this.email});
  @override
  State<VerifyResetOtpScreen> createState() => _VerifyResetOtpScreenState();
}

class _VerifyResetOtpScreenState extends State<VerifyResetOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  int _seconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    _seconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _seconds--);
      if (_seconds == 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.verifyPasswordResetOtp(widget.email, _code.text);
      if (!mounted) {
        await SupabaseService.endPasswordRecovery();
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NewPasswordScreen()),
      );
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await SupabaseService.sendPasswordReset(widget.email);
      if (!mounted) return;
      _code.clear();
      setState(_startCooldown);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been requested.')),
      );
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AuthCanvas(
      heroTitle: 'One small step.\nA safe connection.',
      heroSubtitle: 'Verify your email to continue.',
      children: [
        const Text(
          'Verify your email',
          style: TextStyle(fontFamily: 'MaakSerif', fontSize: 27),
        ),
        const SizedBox(height: 12),
        Text(
          'Enter the verification code sent to ${widget.email}',
          style: const TextStyle(height: 1.5),
        ),
        const SizedBox(height: 22),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
                validator: (v) => RegExp(r'^\d{6,8}$').hasMatch(v ?? '')
                    ? null
                    : 'Enter the code from your email',
              ),
              const SizedBox(height: 22),
              PrimaryButton('Verify code', busy: _busy, onPressed: _verify),
              TextButton(
                onPressed: _busy || _seconds > 0 ? null : _resend,
                child: Text(
                  _seconds > 0 ? 'Resend code in ${_seconds}s' : 'Resend code',
                ),
              ),
              const PrivacyNote(),
            ],
          ),
        ),
      ],
    ),
  );
}
