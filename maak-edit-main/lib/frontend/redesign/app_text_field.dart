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

  /// Optional external key so a screen can re-validate this field
  /// after an async check (e.g. "email already registered").
  final GlobalKey<FormFieldState<String>>? formFieldKey;

  /// Called when the field loses focus (tap outside or keyboard Tab).
  final ValueChanged<String>? onBlur;

  /// Optional inline action shown next to a specific error message.
  final Widget? Function(String error)? errorAction;

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
    this.formFieldKey,
    this.onBlur,
    this.errorAction,
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
      key: widget.formFieldKey ?? _fieldKey,
      initialValue: widget.controller.text,
      validator: (_) {
        // Any explicit validation (form submit / Continue) reveals the
        // error, even if the user never typed in this field.
        _interacted = true;
        return widget.validator?.call(widget.controller.text);
      },
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

        final showError = field.hasError && _interacted;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              // Wrapper only listens for blur; it is never focused itself.
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (hasFocus) {
                if (hasFocus || !_interacted) return;
                field.didChange(widget.controller.text);
                field.validate();
                widget.onBlur?.call(widget.controller.text);
              },
              child: TextField(
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
            ),

            // Error message now sits BELOW the input.
            if (showError)
              FieldErrorNotice(
                field.errorText!,
                action: widget.errorAction?.call(field.errorText!),
              ),
          ],
        );
      },
    );
  }
}

/// Inline field error shown directly BELOW its input:
/// plain red text with a small icon (no box, background or border).
/// [action] is an optional inline link, e.g. "Log in".
class FieldErrorNotice extends StatelessWidget {
  final String message;
  final Widget? action;
  const FieldErrorNotice(this.message, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Semantics(
    // Announced politely by screen readers (aria-live on web).
    liveRegion: true,
    child: Padding(
      // Directional padding so it aligns correctly in RTL and LTR.
      padding: const EdgeInsetsDirectional.only(top: 6, start: 4, end: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(top: 1),
            child: Icon(Icons.error_outline, color: AppColors.error, size: 15),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (action != null) action!,
              ],
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
             // Error message now sits BELOW the dropdown.
             if (field.hasError) FieldErrorNotice(field.errorText!),
           ],
         ),
       );
}