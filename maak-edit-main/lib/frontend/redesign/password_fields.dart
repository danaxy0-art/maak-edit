import 'app_text_field.dart';
import 'package:flutter/material.dart';
import '../../backend/validation/password_policy.dart';
import '../../backend/validation/form_policy.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

class PasswordFields extends StatefulWidget {
  final TextEditingController password, confirmation;
  final bool enabled;
  final String label;
  const PasswordFields({
    super.key,
    required this.password,
    required this.confirmation,
    this.enabled = true,
    this.label = 'Password',
  });
  @override
  State<PasswordFields> createState() => _PasswordFieldsState();
}

class _PasswordFieldsState extends State<PasswordFields> {
  bool _hidden = true, _confirmHidden = true;
  final _confirmationKey = GlobalKey<FormFieldState<String>>();
  @override
  void initState() {
    super.initState();
    widget.password.addListener(_changed);
    widget.confirmation.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.password.removeListener(_changed);
    widget.confirmation.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.password.text;
    final rules = <String, bool>{
      '8+ characters': p.length >= 8,
      'Uppercase letter': RegExp(r'[A-Z]').hasMatch(p),
      'Number': RegExp(r'[0-9]').hasMatch(p),
      'Symbol (e.g. ! @ # \$)': RegExp(r'[^a-zA-Z0-9\s]').hasMatch(p),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(widget.label, requiredField: true),
        AppTextField(
          controller: widget.password,
          enabled: widget.enabled,
          obscureText: _hidden,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.newPassword],
          validator: validateNewPassword,
          decoration: InputDecoration(
            hintText: 'Create a strong password',
            suffixIcon: IconButton(
              tooltip: _hidden ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(
                _hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final rule in rules.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  rule.value
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: rule.value ? AppColors.success : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  rule.key,
                  style: TextStyle(
                    fontSize: 13,
                    color: rule.value ? AppColors.success : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        FieldLabel(
          'Re-enter ${widget.label.toLowerCase()}',
          requiredField: true,
        ),
        AppTextField(
          key: _confirmationKey,
          controller: widget.confirmation,
          enabled: widget.enabled,
          obscureText: _confirmHidden,
          autocorrect: false,
          enableSuggestions: false,
          validator: (v) => validateConfirmation(v, widget.password.text),
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            suffixIcon: IconButton(
              tooltip: _confirmHidden ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _confirmHidden = !_confirmHidden),
              icon: Icon(
                _confirmHidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            ),
          ),
        ),
        if (widget.confirmation.text.isNotEmpty &&
            widget.confirmation.text == p &&
            validateNewPassword(p) == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 18),
                SizedBox(width: 8),
                Text(
                  'Passwords match',
                  style: TextStyle(color: AppColors.success, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
