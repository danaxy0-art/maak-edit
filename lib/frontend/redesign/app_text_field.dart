import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Validate this field on blur or explicit form submission, never on first tap.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int? maxLines;
  final InputDecoration decoration;

  // Use these only on fields where we want live feedback.
  final bool liveValidation;
  final bool showValidCheck;

  const AppTextField({
    super.key,
    required this.controller,
    this.validator,
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType,
    this.autofillHints,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.decoration = const InputDecoration(),
    this.liveValidation = false,
    this.showValidCheck = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();

  bool _interacted = false;

  bool get _isValid {
    if (!_interacted) return false;

    final value = widget.controller.text;

    if (value.trim().isEmpty) return false;

    return widget.validator?.call(value) == null;
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      key: _fieldKey,
      initialValue: widget.controller.text,
      validator: (_) => widget.validator?.call(widget.controller.text),
      autovalidateMode: AutovalidateMode.disabled,
      builder: (field) {
        final errorBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.error,
            width: 1.5,
          ),
        );

        final successBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.success,
            width: 1.5,
          ),
        );

        final valid =
            widget.showValidCheck &&
            _isValid &&
            !field.hasError;

        Widget? suffixIcon = widget.decoration.suffixIcon;

        // Don't replace an existing suffix icon such as
        // the show/hide password button.
        if (suffixIcon == null) {
          if (valid) {
            suffixIcon = const Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 21,
            );
          } else if (field.hasError && _interacted) {
            suffixIcon = const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 21,
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (field.hasError && _interacted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FieldErrorNotice(field.errorText!),
              ),

            TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              obscureText: widget.obscureText,
              autocorrect: widget.autocorrect,
              enableSuggestions: widget.enableSuggestions,
              keyboardType: widget.keyboardType,
              autofillHints: widget.autofillHints,
              inputFormatters: widget.inputFormatters,
              maxLength: widget.maxLength,
              maxLines: widget.maxLines,

              onChanged: (value) {
                if (!_interacted) {
                  setState(() {
                    _interacted = true;
                  });
                }

                field.didChange(value);

                if (widget.liveValidation) {
                  field.validate();
                }
              },

              onTapOutside: (_) {
                FocusManager.instance.primaryFocus?.unfocus();

                if (!_interacted) {
                  setState(() {
                    _interacted = true;
                  });
                }

                field.didChange(widget.controller.text);
                field.validate();
              },

              decoration: widget.decoration.copyWith(
                suffixIcon: suffixIcon,

                enabledBorder:
                    field.hasError && _interacted
                    ? errorBorder
                    : valid
                    ? successBorder
                    : widget.decoration.enabledBorder,

                focusedBorder:
                    field.hasError && _interacted
                    ? errorBorder
                    : valid
                    ? successBorder
                    : widget.decoration.focusedBorder,
              ),
            ),
          ],
        );
      },
    );
  }
}

class FieldErrorNotice extends StatelessWidget {
  final String message;
  const FieldErrorNotice(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0EF),
        border: Border.all(color: const Color(0xFFF3BCBC)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class AppSelectField<T> extends FormField<T> {
  AppSelectField({
    super.key,
    super.initialValue,
    super.validator,
    required List<DropdownMenuItem<T>>? items,
    required ValueChanged<T?>? onChanged,
    Widget? hint,
    bool isExpanded = true,
    BorderRadius? borderRadius,
    Color? dropdownColor,
    Widget? icon,
    Color? iconEnabledColor,
    TextStyle? style,
    InputDecoration decoration = const InputDecoration(),
  }) : super(
         autovalidateMode: AutovalidateMode.disabled,
         builder: (field) => Column(
           crossAxisAlignment: CrossAxisAlignment.stretch,
           children: [
             if (field.hasError)
               Padding(
                 padding: const EdgeInsets.only(bottom: 8),
                 child: FieldErrorNotice(field.errorText!),
               ),
             InputDecorator(
               decoration: decoration.copyWith(
                 enabled: onChanged != null,
                 enabledBorder: field.hasError
                     ? OutlineInputBorder(
                         borderRadius: BorderRadius.circular(12),
                         borderSide: const BorderSide(color: AppColors.error),
                       )
                     : null,
               ),
               isEmpty: field.value == null && hint == null,
               child: DropdownButtonHideUnderline(
                 child: DropdownButton<T>(
                   value: field.value,
                   items: items,
                   hint: hint,
                   isExpanded: isExpanded,
                   isDense: true,
                   borderRadius: borderRadius ?? BorderRadius.circular(12),
                   dropdownColor: dropdownColor ?? Colors.white,
                   icon: icon ?? const Icon(Icons.expand_more),
                   iconEnabledColor: iconEnabledColor ?? AppColors.textMuted,
                   style:
                       style ??
                       const TextStyle(
                         fontFamily: 'Roboto',
                         color: AppColors.textDark,
                         fontSize: 14,
                       ),
                   onChanged: onChanged == null
                       ? null
                       : (value) {
                           field.didChange(value);
                           field.validate();
                           onChanged(value);
                         },
                 ),
               ),
             ),
           ],
         ),
       );
}
