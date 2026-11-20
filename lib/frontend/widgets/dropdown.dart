import '../redesign/app_text_field.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared dropdown used across the app so every menu has the same look.
/// The closed box is styled by AppTheme's inputDecorationTheme; this widget
/// styles the popup menu (color, corners, arrow, text).
class AppDropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  const AppDropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return AppSelectField<String>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(12),
      dropdownColor: AppColors.fieldFill,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      iconEnabledColor: AppColors.textMuted,
      style: const TextStyle(
        fontFamily: 'Roboto',
        color: AppColors.textDark,
        fontSize: 15,
      ),
      decoration: InputDecoration(hintText: hint),
      items: options
          .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }
}
