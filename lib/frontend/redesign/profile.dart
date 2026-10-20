import 'app_text_field.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../auth/welcome_screen.dart';
import '../auth/auth_gate.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'multi_condition_field.dart';
import 'registration.dart';
import 'feedback.dart';

class ProfilePage extends StatefulWidget {
  final String role;
  const ProfilePage({super.key, required this.role});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}


class _ProfilePageState extends State<ProfilePage> {
  late Future<Map<String, dynamic>> _future;

  // Prevent duplicate deletion requests while the operation is running.
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Load the profile information for the current user.
  void _load() =>
      _future = SupabaseService.loadProfileForEdit(role: widget.role);

  // Open the edit profile screen and refresh the profile after saving.
  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(role: widget.role),
      ),
    );

    if (saved == true && mounted) {
      setState(_load);
    }
  }

  
  /// Displays a clear warning before permanent account deletion.
  /// Requires explicit acknowledgment to prevent accidental deletion.
  Future<void> _confirmDeleteAccount() async {
    if (_deletingAccount) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Track acknowledgment inside the dialog only.
        bool acknowledged = false;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),

            // Highlight the destructive nature of the action.
            title: const Column(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0xFFFFE8E6),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFB42318),
                    size: 34,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Permanently delete your account?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'MaakSerif',
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This action is permanent and cannot be undone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Explain the consequences before asking for consent.
                    const Text(
                      'Deleting your account will remove:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    const _DeleteInfoRow(
                      'Your profile and personal information',
                    ),
                    const _DeleteInfoRow(
                      'Your account and associated data',
                    ),

                    // Verification documents apply to volunteers only.
                    if (widget.role == 'volunteer')
                      const _DeleteInfoRow(
                        'Your verification documents',
                      ),

                    const SizedBox(height: 16),

                    // A distinct warning reinforces the irreversible action.
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Color(0xFFB42318),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'You will permanently lose access to this account.',
                              style: TextStyle(
                                color: Color(0xFF912018),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Require an intentional acknowledgment.
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: acknowledged,
                      onChanged: (value) {
                        setDialogState(
                          () => acknowledged = value ?? false,
                        );
                      },
                      title: const Text(
                        'I understand that this action is permanent.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Provide a safe exit and disable deletion until acknowledged.
            actions: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: acknowledged
                        ? () => Navigator.pop(dialogContext, true)
                        : null,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete account permanently'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB42318),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE6B9B5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Keep my account'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    // Cancel or close the dialog without deleting the account.
    if (confirmed != true || !mounted) return;

    // Delete only after explicit user confirmation.
    await _deleteAccount();
  }


  /// Requests permanent account deletion through the Supabase service.
  /// Navigates to the welcome screen only after successful deletion.
  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;

    // Disable repeated actions and display a loading indicator.
    setState(() => _deletingAccount = true);

    try {
      // The Edge Function verifies the user and deletes their account.
      await SupabaseService.deleteAccount();

      if (!mounted) return;

      // Remove the profile screen from the navigation history.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const WelcomeScreen(),
        ),
        (_) => false,
      );
    } catch (e) {
      // Keep the user on the current screen if deletion fails.
      if (mounted) {
        showAppError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _deletingAccount = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Prevent leaving the screen while account deletion is in progress.
    canPop: !_deletingAccount,
    child: BotanicalScaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        automaticallyImplyLeading: false,
      ),
      body: ResponsiveBody(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, s) {
            if (s.hasError) {
              return EmptyState(
                'Could not load profile',
                friendlyError(s.error!),
                retry: () => setState(_load),
              );
            }

            if (!s.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final p = s.data!;
            final volunteer = widget.role == 'volunteer';

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 28),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFFCDDEF5),
                    child: Text(
                      initials(p['full_name'] as String? ?? ''),
                      style: const TextStyle(
                        fontFamily: 'MaakSerif',
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  p['full_name'] as String? ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'MaakSerif',
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: RoleChip(
                    volunteer ? 'Volunteer' : 'Help seeker',
                  ),
                ),
                const SizedBox(height: 26),
                _row(
                  Icons.mail_outline,
                  'Email',
                  p['email'],
                ),
                _row(
                  Icons.favorite_border,
                  volunteer
                      ? 'Condition experience'
                      : 'Chronic condition',
                  (p['conditions'] as List?)?.join(', ') ??
                      p['condition'],
                ),
                _row(
                  Icons.language,
                  'Preferred language',
                  p['preferred_language'],
                ),
                _row(
                  Icons.description_outlined,
                  volunteer ? 'My experience' : 'About me',
                  p[volunteer ? 'experience' : 'description'],
                ),
                const SizedBox(height: 10),

                // Existing profile editing action.
                PrimaryButton(
                  'Edit profile',
                  icon: Icons.edit_outlined,
                  onPressed: _deletingAccount ? null : _edit,
                ),
                const SizedBox(height: 14),

                // Existing logout action.
                TextButton.icon(
                  onPressed: _deletingAccount
                      ? null
                      : () => logout(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Destructive action is visually separated from
                // regular profile actions to prevent accidental taps.
                TextButton.icon(
                  onPressed: _deletingAccount
                      ? null
                      : _confirmDeleteAccount,
                  icon: _deletingAccount
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _deletingAccount
                        ? 'Deleting account...'
                        : 'Delete account',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  // Display one profile field using the existing app design.
  Widget _row(IconData icon, String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: AppColors.primaryNavy,
            size: 22,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value == null || value.toString().isEmpty
                      ? 'Not provided'
                      : value.toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}


/// Displays an item describing data affected by account deletion.
class _DeleteInfoRow extends StatelessWidget {
  final String text;

  const _DeleteInfoRow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 19,
          color: AppColors.primaryNavy,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    ),
  );
}


Future<void> logout(BuildContext context) async {
  try {
    await SupabaseService.signOut();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    }
  } catch (e) {
    if (context.mounted) showAppError(context, e);
  }
}

class EditProfilePage extends StatefulWidget {
  final String role;
  final bool reapply;
  const EditProfilePage({super.key, required this.role, this.reapply = false});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _about = TextEditingController();
  List<String> _conditions = [];
  String? _language, _document;
  bool _aiConsent = false;
  PlatformFile? _file;
  bool _ready = false, _busy = false;
  Object? _error;
  bool get volunteer => widget.role == 'volunteer';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await SupabaseService.loadProfileForEdit(role: widget.role);
      if (!mounted) return;
      setState(() {
        _name.text = p['full_name'] as String? ?? '';
        _about.text =
            p[volunteer ? 'experience' : 'description'] as String? ?? '';
        _conditions = List<String>.from(p['conditions'] as List);
        _aiConsent = p['ai_matching_consent'] == true;
        // القديم _language = p['preferred_language'] as String?;
        //الجديد
        final savedLanguage = p['preferred_language'] as String?;
        // Old/unsupported values (e.g. 'French') fall back to English.
        _language = savedLanguage == null || languages.contains(savedLanguage)
            ? savedLanguage
            : 'English';

        _document = p['verification_document_url'] as String?;
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (result == null || !mounted) return;
      if (result.files.single.size > 5242880) {
        throw ArgumentError('Choose a document smaller than 5 MB.');
      }
      setState(() => _file = result.files.single);
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      String? uploaded;
      if (_file != null) {
        if (_file!.bytes == null) {
          throw ArgumentError('Select the document again.');
        }
        uploaded = await SupabaseService.uploadVerificationDocument(
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
        language: _language!,
        description: _about.text,
        document: uploaded,
        reapply: widget.reapply,
      );
      if (!mounted) return;
      showSuccess(
        context,
        widget.reapply
            ? 'Application resubmitted for review.'
            : 'Profile updated.',
      );
      if (widget.reapply) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showAppError(context, e, retry: _save);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: BotanicalScaffold(
      appBar: AppBar(
        title: Text(widget.reapply ? 'Update and reapply' : 'Edit profile'),
      ),
      body: ResponsiveBody(
        child: _error != null
            ? EmptyState(
                'Could not load profile',
                friendlyError(_error!),
                retry: _load,
              )
            : !_ready
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  FormSheet(
                    child: Form(
                      key: _form,
                      autovalidateMode: AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('Full name', requiredField: true),
                          AppTextField(
                            controller: _name,
                            maxLength: 30,
                            validator: validateName,
                            enabled: !_busy,
                            liveValidation: true,
                            showValidCheck: true,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              hintText: 'Your full name',
                              counterText: '',
                            ),
                          ),
                          FieldLabel(
                            volunteer
                                ? 'Condition experience'
                                : 'Chronic condition',
                            requiredField: true,
                          ),
                          MultiConditionField(
                            values: _conditions,
                            enabled: !_busy,
                            onChanged: (v) => setState(() => _conditions = v),
                          ),
                          if (volunteer)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _aiConsent,
                              onChanged: _busy
                                  ? null
                                  : (v) =>
                                        setState(() => _aiConsent = v ?? false),
                              title: const Text(
                                'Allow AI experience comparison',
                              ),
                              subtitle: const Text(
                                'Your experience description may be sent to Google Gemini when a help seeker requests AI matching. Do not include names, contact details or documents.',
                              ),
                            ),
                          const FieldLabel(
                            'Preferred language',
                            requiredField: true,
                          ),
                          AppSelectField<String>(
                            initialValue: _language,
                            isExpanded: true,
                            items: languages
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _language = v),
                            validator: (v) =>
                                v == null ? 'Select your language' : null,
                          ),
                          FieldLabel(
                            volunteer
                                ? 'My lived experience'
                                : 'About me (optional)',
                            requiredField: volunteer,
                          ),
                          AppTextField(
                            controller: _about,
                            maxLength: 300,
                            maxLines: 4,
                            enabled: !_busy,
                            liveValidation: volunteer,
                            showValidCheck: volunteer,
                            validator: (v) =>
                                volunteer && (v == null || v.trim().isEmpty)
                                ? 'Describe your experience'
                                : null,
                          ),
                          if (widget.reapply) ...[
                            const FieldLabel(
                              'Verification document',
                              requiredField: true,
                            ),
                            FormField<bool>(
                              validator: (_) =>
                                  _file == null &&
                                      (_document == null || _document!.isEmpty)
                                  ? 'Upload a document'
                                  : null,
                              builder: (s) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _pick,
                                    icon: const Icon(Icons.upload_file),
                                    label: Text(
                                      _file?.name ??
                                          'Replace verification document',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Your previous document is kept unless you upload a replacement.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  if (s.hasError)
                                    FieldErrorNotice(s.errorText!),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          PrimaryButton(
                            widget.reapply
                                ? 'Resubmit application'
                                : 'Save changes',
                            busy: _busy,
                            onPressed: _save,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
