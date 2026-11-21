import 'app_text_field.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../auth/welcome_screen.dart';
import '../auth/auth_gate.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'ai_consent.dart';
import 'multi_condition_field.dart';
import 'registration.dart';
import 'feedback.dart';
import 'profile_avatar.dart';

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
      MaterialPageRoute(builder: (_) => EditProfilePage(role: widget.role)),
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
            actionsAlignment: MainAxisAlignment.center,
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
                    fontFamily: 'DMSans',
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
                    const _DeleteInfoRow('Your account and associated data'),

                    // Verification documents apply to volunteers only.
                    if (widget.role == 'volunteer')
                      const _DeleteInfoRow('Your verification documents'),

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
                          Icon(Icons.error_outline, color: Color(0xFFB42318)),
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
                        setDialogState(() => acknowledged = value ?? false);
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
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
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

  // Account actions are separated from profile details to reduce clutter.
  Future<void> _openAccountSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _AccountSettingsPage(
          deletingAccount: _deletingAccount,
          onDelete: _confirmDeleteAccount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deletingAccount,
    child: BotanicalScaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Account settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _deletingAccount ? null : _openAccountSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ResponsiveBody(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EmptyState(
                'Could not load profile',
                friendlyError(snapshot.error!),
                retry: () => setState(_load),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snapshot.data!;
            final isVolunteer = widget.role == 'volunteer';
            final conditions =
                (profile['conditions'] as List?)?.join(', ') ??
                profile['condition']?.toString() ??
                'Not provided';
            final bio = profile[isVolunteer ? 'experience' : 'description'];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  children: [
                    ProfileAvatarEditor(
                      name: profile['full_name'] as String? ?? '',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile['full_name'] as String? ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'MaakSerif',
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // A labeled badge communicates the role without
                          // relying on color alone.
                          RoleChip(isVolunteer ? 'Volunteer' : 'Help seeker'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _deletingAccount ? null : _edit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (profile['setup_incomplete'] == true)
                  const FieldErrorNotice(
                    'Your basic profile is available. The administrator must apply the database updates before you can save condition changes.',
                  ),
                if (profile['profile_complete'] != true) ...[
                  const FieldErrorNotice(
                    'Your profile has not been completed yet.',
                  ),
                  PrimaryButton(
                    'Complete my profile',
                    onPressed: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute<void>(
                            builder: (_) => RegistrationScreen(
                              role: widget.role,
                              completionOnly: true,
                            ),
                          ),
                        )
                        .then((_) {
                          if (mounted) setState(_load);
                        }),
                  ),
                ],
                for (final review
                    in (profile['condition_reviews'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurfaceCard(
                      child: Text(
                        'Condition: ${review['submitted_name']}\nStatus: ${review['status']}${review['reason'] == null ? '' : '\nReason: ${review['reason']}'}',
                      ),
                    ),
                  ),
                if (widget.role != 'admin') const AiMatchingSettings(),
                const SizedBox(height: 12),
                Text(
                  'PERSONAL INFORMATION',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _infoTile(Icons.mail_outline, 'Email', profile['email']),
                      const Divider(height: 1),
                      _infoTile(
                        Icons.favorite_border,
                        isVolunteer
                            ? 'Condition experience'
                            : 'Chronic conditions',
                        conditions,
                      ),
                      const Divider(height: 1),
                      _infoTile(
                        Icons.language,
                        'Preferred language',
                        profile['preferred_language'],
                      ),
                      const Divider(height: 1),
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: const Icon(
                          Icons.notes_outlined,
                          color: AppColors.primaryNavy,
                        ),
                        title: Text(isVolunteer ? 'My experience' : 'About me'),
                        subtitle: Text(
                          bio == null || bio.toString().trim().isEmpty
                              ? 'Not provided'
                              : bio.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              bio == null || bio.toString().trim().isEmpty
                                  ? 'Not provided'
                                  : bio.toString(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.settings_outlined,
                      color: AppColors.primaryNavy,
                    ),
                    title: const Text('Account settings'),
                    subtitle: const Text('Log out or manage your account'),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !_deletingAccount,
                    onTap: _openAccountSettings,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _infoTile(IconData icon, String title, dynamic value) => ListTile(
    dense: true,
    leading: Icon(icon, color: AppColors.primaryNavy),
    title: Text(title),
    subtitle: Text(
      value == null || value.toString().trim().isEmpty
          ? 'Not provided'
          : value.toString(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// A focused settings screen keeps destructive actions away from daily editing.
class _AccountSettingsPage extends StatelessWidget {
  final bool deletingAccount;
  final Future<void> Function() onDelete;

  const _AccountSettingsPage({
    required this.deletingAccount,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Account settings')),
    body: ResponsiveBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.primaryNavy),
              title: const Text('Log out'),
              subtitle: const Text('Sign out of your account'),
              trailing: const Icon(Icons.chevron_right),
              enabled: !deletingAccount,
              onTap: () => logout(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'ACCOUNT MANAGEMENT',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Delete account',
                style: TextStyle(color: AppColors.error),
              ),
              subtitle: const Text('Permanently remove your account'),
              trailing: const Icon(Icons.chevron_right, color: AppColors.error),
              enabled: !deletingAccount,
              onTap: onDelete,
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
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    ),
  );
}

bool _logoutInProgress = false;

/// Shared by both roles, pending/rejected volunteers, and the admin screen.
Future<void> logout(BuildContext context) async {
  if (!context.mounted || _logoutInProgress) return;
  _logoutInProgress = true;
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Match the account deletion dialog's shape and spacing.
        actionsAlignment: MainAxisAlignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Color(0xFFFFE8E6),
              child: Icon(
                Icons.logout_rounded,
                color: Color(0xFFB42318),
                size: 30,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Log out?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420),
          child: Text(
            "Are you sure you want to log out of Ma'ak?",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB42318),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                autofocus: true,
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await SupabaseService.signOut();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    }
  } catch (e) {
    if (context.mounted) showAppError(context, e);
  } finally {
    _logoutInProgress = false;
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
  final _otherName = TextEditingController();
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
    _otherName.dispose();
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
        _otherName.text = p['other_name'] as String? ?? '';
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
        otherName: _conditions.contains('Other') ? _otherName.text : null,
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
      // Keep the save action visible while the form itself scrolls as needed.
      bottomNavigationBar: !_ready || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PrimaryButton(
                  widget.reapply ? 'Resubmit application' : 'Save changes',
                  busy: _busy,
                  onPressed: _save,
                ),
              ),
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
            : Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    FormSheet(
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
                            otherController: _otherName,
                            enabled: !_busy,
                            onChanged: (v) => setState(() => _conditions = v),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => showAiMatchingDetails(context),
                              icon: const Icon(Icons.info_outline, size: 18),
                              label: const Text('AI matching details'),
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
                                  (language) => DropdownMenuItem(
                                    value: language,
                                    child: Text(language),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _language = value),
                            validator: (value) =>
                                value == null ? 'Select your language' : null,
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
                            maxLines: 2,
                            enabled: !_busy,
                            liveValidation: volunteer,
                            showValidCheck: volunteer,
                            validator: (value) =>
                                volunteer &&
                                    (value == null || value.trim().isEmpty)
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
                              builder: (field) => Column(
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
                                  if (field.hasError)
                                    FieldErrorNotice(field.errorText!),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}
