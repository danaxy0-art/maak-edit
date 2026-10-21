import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_text_field.dart';

/// Multi-line form field in Ma'ak's validation style: an inline red notice
/// above the field and a red border when invalid. Unlike AppTextField, it also
/// shows its error when the form is submitted before the field was touched,
/// which required explanations (appeals, decisions) need.
class ValidatedTextArea extends StatelessWidget {
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool enabled;
  final int maxLength;
  final int maxLines;
  final int minLines;
  final String? hintText;
  final String? helperText;

  const ValidatedTextArea({
    super.key,
    required this.controller,
    required this.validator,
    required this.maxLength,
    this.enabled = true,
    this.maxLines = 5,
    this.minLines = 3,
    this.hintText,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) => FormField<String>(
    initialValue: controller.text,
    validator: (_) => validator(controller.text),
    autovalidateMode: AutovalidateMode.disabled,
    builder: (field) {
      final errorBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FieldErrorNotice(field.errorText!),
            ),
          TextField(
            controller: controller,
            enabled: enabled,
            maxLength: maxLength,
            maxLines: maxLines,
            minLines: minLines,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) {
              final hadError = field.hasError;
              field.didChange(value);
              if (hadError) field.validate();
            },
            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              if (controller.text.isNotEmpty) {
                field.didChange(controller.text);
                field.validate();
              }
            },
            decoration: InputDecoration(
              hintText: hintText,
              helperText: helperText,
              helperMaxLines: 3,
              enabledBorder: field.hasError ? errorBorder : null,
              focusedBorder: field.hasError ? errorBorder : null,
              suffixIcon: field.hasError
                  ? const Icon(Icons.error_outline, color: AppColors.error)
                  : null,
            ),
          ),
        ],
      );
    },
  );
}
