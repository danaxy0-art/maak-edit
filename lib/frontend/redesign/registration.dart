import '../../backend/validation/debounced_action.dart';
import 'app_text_field.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../auth/auth_gate.dart';
import '../theme/app_theme.dart';
import '../widgets/maak_logo.dart';
import 'multi_condition_field.dart';
import 'feedback.dart';
import 'password_fields.dart';
import 'ui.dart';

const languages = ['Arabic', 'English'];

class RegistrationScreen extends StatefulWidget {
  final String role;
  final bool completionOnly;
  const RegistrationScreen({
    super.key,
    required this.role,
    this.completionOnly = false,
  });
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _accountForm = GlobalKey<FormState>(),
      _preferencesForm = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  final _password = TextEditingController(),
      _confirmation = TextEditingController(),
      _about = TextEditingController();
  final _otherName = TextEditingController();
  List<String> _conditions = [];
  String? _language;
  bool _aiConsent = false;
  final _emailKey = GlobalKey<FormFieldState<String>>();
  String? _checkedEmail, _emailError;
  bool _emailChecking = false;
  int _emailCheckVersion = 0;
  final _emailDebounce = DebouncedAction();
  bool get _emailAvailable =>
      !_emailChecking &&
      _checkedEmail == _normalizedEmail() &&
      _emailError == null;

  String _normalizedEmail() => normalizeEmail(_email.text);
  void _emailChanged(String value) {
    _emailCheckVersion++;
    _emailDebounce.cancel();
    _emailKey.currentState?.reset();
    setState(() {
      _checkedEmail = null;
      _emailError = null;
      _emailChecking = false;
    });
    if (validateEmail(value) == null) {
      _emailDebounce.schedule(() {
        if (mounted && _step == 0) _checkEmail();
      });
    }
  }

  Future<bool> _checkEmail({bool force = false}) async {
    _emailDebounce.cancel();
    final email = _normalizedEmail();
    if (validateEmail(email) != null) return false;
    if (!force &&
        _checkedEmail == email &&
        (_emailError == null ||
            _emailError!.startsWith('This email is already')))
      return _emailError == null;
    final version = ++_emailCheckVersion;
    setState(() {
      _emailChecking = true;
      _emailError = null;
    });
    String? error;
    try {
      if (await SupabaseService.registrationEmailExists(email))
        error = 'This email is already registered. Please log in.';
    } catch (e) {
      error = e is FunctionException && e.status == 429
          ? 'Too many checks. Please wait before trying again.'
          : 'Could not check this email. Please try again.';
    }
    if (!mounted ||
        version != _emailCheckVersion ||
        email != _normalizedEmail())
      return false;
    setState(() {
      _emailChecking = false;
      _checkedEmail = email;
      _emailError = error;
    });
    _emailKey.currentState?.validate();
    return error == null;
  }

  PlatformFile? _file;
  int _step = 0;
  bool _busy = false, _created = false;
  String? _uploadedPath;
  bool get _volunteer => widget.role == 'volunteer';
  @override
  void initState() {
    super.initState();
    if (widget.completionOnly) {
      _created = true;
      _step = 1;
      final user = SupabaseService.currentUser;
      _name.text = user?.userMetadata?['full_name'] as String? ?? '';
      _email.text = user?.email ?? '';
      _loadIncomplete();
    }
  }

  Future<void> _loadIncomplete() async {
    try {
      final data = await SupabaseService.loadProfileForEdit(role: widget.role);
      if (!mounted) return;
      setState(() {
        _name.text = data['full_name'] as String? ?? _name.text;
      });
    } catch (e) {
      if (mounted) showAppError(context, e, retry: _loadIncomplete);
    }
  }

  @override
  void dispose() {
    _emailDebounce.cancel();
    _emailCheckVersion++;
    for (final c in [
      _name,
      _email,
      _password,
      _confirmation,
      _about,
      _otherName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    if (_emailChecking || _busy) return;
    setState(() {
      _emailError = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_accountForm.currentState!.validate()) return;
    if (!await _checkEmail(force: true)) return;
    if (mounted) setState(() => _step = 1);
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (result == null || !mounted) return;
      if (result.files.single.size > 5 * 1024 * 1024) {
        throw ArgumentError('Choose a document smaller than 5 MB.');
      }
      setState(() {
        _file = result.files.single;
        _uploadedPath = null;
      });
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  Future<void> _create() async {
    if (_busy || !_preferencesForm.currentState!.validate()) return;
    if (_conditions.isEmpty || _language == null) return;
    if (_volunteer && _file == null) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      if (!_created) {
        final response = await SupabaseService.signUp(
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
          role: widget.role,
        );
        if (response.user == null) throw StateError('Could not create account');
        _created = true;
        // Never persist health preferences until there is a verified session.
        if (response.session == null) {
          if (!mounted) return;
          final verified = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => VerifySignupScreen(email: _email.text),
            ),
          );
          if (verified != true) return;
        }
      }
      if (SupabaseService.currentUser == null) {
        if (!mounted) return;
        final verified = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => VerifySignupScreen(email: _email.text),
          ),
        );
        if (verified != true) return;
      }
      if (_volunteer && _uploadedPath == null) {
        if (_file?.bytes == null) {
          throw ArgumentError('Please select the document again.');
        }
        _uploadedPath = await SupabaseService.uploadVerificationDocument(
          fileBytes: _file!.bytes!,
          fileName: _file!.name,
        );
      }
      await SupabaseService.saveProfile(
        fullName: _name.text,
        role: widget.role,
        condition: _conditions.first,
        conditions: _conditions,
        aiConsent: _aiConsent,
        otherName: _conditions.contains('Other') ? _otherName.text : null,
        language: _language!,
        description: _about.text,
        document: _uploadedPath,
      );
      if (_volunteer) {
        final application = await SupabaseService.getMyVolunteerApplication();
        if (application == null) {
          throw StateError(
            'Your application could not be confirmed. Please retry submission.',
          );
        }
        // The application is saved; a failed optional email must not block it.
        // The server sends it only to this signed-in volunteer's own address.
        try {
          await SupabaseService.sendVolunteerEmail(status: 'pending');
        } catch (e) {
          debugPrint('Volunteer pending email failed: $e');
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } catch (e) {
      final duplicate =
          (e is ArgumentError &&
              e.message.toString().contains(
                'This email is already registered',
              )) ||
          (e is AuthException &&
              (e.code == 'user_already_exists' || e.code == 'email_exists'));
      if (mounted && duplicate) {
        // If another signup claimed the address after the live check, return to
        // the actual email field instead of a late dialog on Preferences.
        setState(() {
          _step = 0;
          _checkedEmail = _normalizedEmail();
          _emailError = 'This email is already registered. Please log in.';
          _emailChecking = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _emailKey.currentState?.validate();
        });
      } else if (mounted) {
        showAppError(context, e, retry: _create);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AuthCanvas(
      heroTitle: _step == 0
          ? 'A little support.\nA stronger you.'
          : 'Support that\nunderstands you.',
      heroSubtitle: _step == 0
          ? 'Create an account and find your community.'
          : 'Tell us what feels right for you.',
      heroHeight: 290,
      progress: RegistrationProgress(
        step: _step,
        onAccountTap: _step == 1 && !_created
            ? () => setState(() => _step = 0)
            : null,
      ),
      children: [
        Text(
          _step == 0
              ? 'Create your account'
              : _volunteer
              ? 'Share your experience'
              : 'Your support preferences',
          style: const TextStyle(
            fontFamily: 'MaakSerif',
            fontSize: 25,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        if (_step == 0)
          Form(
            key: _accountForm,
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Full name', requiredField: true),
                AppTextField(
                  controller: _name,
                  maxLength: fullNameLimit,
                  validator: validateName,
                  liveValidation: false,
                  showValidCheck: true,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    hintText: 'Your full name',
                    counterText: '',
                  ),
                ),
                const FieldLabel('Email', requiredField: true),
                AppTextField(
                  controller: _email,
                  formFieldKey: _emailKey,
                  maxLength: 254,
                  showCounter: false,
                  onChanged: _emailChanged,
                  onBlur: (_) {
                    _checkEmail();
                  },
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      validateEmail(v) ??
                      (_checkedEmail == _normalizedEmail()
                          ? _emailError
                          : null),
                  liveValidation: false,
                  showValidCheck:
                      !_emailChecking &&
                      _checkedEmail == _normalizedEmail() &&
                      _emailError == null,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                  ),
                ),
                if (_emailChecking)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Checking email...',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                PasswordFields(
                  password: _password,
                  confirmation: _confirmation,
                ),
                const SizedBox(height: 26),
                PrimaryButton(
                  'Continue',
                  busy: _emailChecking,
                  onPressed: _emailAvailable ? _next : null,
                  icon: Icons.arrow_forward,
                ),
              ],
            ),
          )
        else
          Form(
            key: _preferencesForm,
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: RoleChip(_volunteer ? 'Volunteer' : 'Help seeker'),
                ),
                if (widget.completionOnly) ...[
                  const FieldLabel('Full name', requiredField: true),
                  AppTextField(
                    controller: _name,
                    maxLength: fullNameLimit,
                    validator: validateName,
                  ),
                ],
                FieldLabel(
                  _volunteer
                      ? 'Chronic condition experience'
                      : 'Chronic condition',
                  requiredField: true,
                ),
                MultiConditionField(
                  values: _conditions,
                  otherController: _otherName,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _conditions = v),
                ),
                if (_volunteer)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _aiConsent,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _aiConsent = v ?? false),
                    title: const Text('Allow AI experience comparison'),
                    subtitle: const Text(
                      'Your experience description may be sent to Google Gemini when a help seeker requests AI matching. Do not include names, contact details or documents.',
                    ),
                  ),
                const FieldLabel('Preferred language', requiredField: true),
                AppSelectField<String>(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.language_outlined),
                  ),
                  initialValue: _language,
                  isExpanded: true,
                  hint: const Text('Select language'),
                  items: languages
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _language = v),
                  validator: (v) =>
                      v == null ? 'Choose your preferred language' : null,
                ),
                FieldLabel(
                  _volunteer ? 'Your lived experience' : 'About you (optional)',
                  requiredField: _volunteer,
                ),
                AppTextField(
                  controller: _about,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: InputDecoration(
                    hintText: _volunteer
                        ? 'How can your experience support someone else?'
                        : 'What kind of support are you looking for?',
                  ),
                  validator: (v) =>
                      _volunteer && (v == null || v.trim().isEmpty)
                      ? 'Describe your lived experience'
                      : null,
                ),
                if (_volunteer) ...[
                  const FieldLabel(
                    'Verification document',
                    requiredField: true,
                  ),
                  FormField<PlatformFile>(
                    validator: (_) =>
                        _file == null ? 'Upload a verification document' : null,
                    builder: (state) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pick,
                          icon: const Icon(Icons.upload_file),
                          label: Text(
                            _file?.name ?? 'Upload document',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'PDF, PNG or JPG · Max 5 MB',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (state.hasError) FieldErrorNotice(state.errorText!),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                PrimaryButton(
                  _created
                      ? 'Complete registration'
                      : _volunteer
                      ? 'Submit application'
                      : 'Create account',
                  busy: _busy,
                  onPressed: _create,
                ),
                const PrivacyNote(),
              ],
            ),
          ),
      ],
    ),
  );
}

class VerifySignupScreen extends StatefulWidget {
  final String email;
  const VerifySignupScreen({super.key, required this.email});
  @override
  State<VerifySignupScreen> createState() => _VerifySignupScreenState();
}

class _VerifySignupScreenState extends State<VerifySignupScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6 || _busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.verifySignup(widget.email, _code.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await SupabaseService.resendSignup(widget.email);
      if (mounted) showSuccess(context, 'A new code has been requested.');
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthCanvas(
    children: [
      const MaakLogo(),
      const SizedBox(height: 30),
      const Icon(
        Icons.mark_email_read_outlined,
        size: 60,
        color: AppColors.primaryNavy,
      ),
      const SizedBox(height: 22),
      const Text(
        'Verify your email',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'MaakSerif',
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Enter the code sent to ${widget.email}.',
        textAlign: TextAlign.center,
      ),
      const FieldLabel('Verification code', requiredField: true),
      TextField(
        controller: _code,
        keyboardType: TextInputType.number,
        maxLength: 8,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(hintText: 'Email code'),
      ),
      const SizedBox(height: 18),
      PrimaryButton('Verify and continue', busy: _busy, onPressed: _verify),
      TextButton(
        onPressed: _busy ? null : _resend,
        child: const Text('Resend code'),
      ),
    ],
  );
}
