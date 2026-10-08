import 'app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../auth/welcome_screen.dart';
import '../auth/auth_gate.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'condition_field.dart';
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
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() =>
      _future = SupabaseService.loadProfileForEdit(role: widget.role);
  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(role: widget.role)),
    );
    if (saved == true && mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
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
            return const Center(child: CircularProgressIndicator());
          }
          final p = s.data!, volunteer = widget.role == 'volunteer';
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
              Center(child: RoleChip(volunteer ? 'Volunteer' : 'Help seeker')),
              const SizedBox(height: 26),
              _row(Icons.mail_outline, 'Email', p['email']),
              _row(
                Icons.favorite_border,
                volunteer ? 'Condition experience' : 'Chronic condition',
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
              PrimaryButton(
                'Edit profile',
                icon: Icons.edit_outlined,
                onPressed: _edit,
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () => logout(context),
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
              ),
            ],
          );
        },
      ),
    ),
  );
  Widget _row(IconData icon, String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryNavy, size: 22),
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
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
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
  String? _condition, _language, _document;
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
        _condition = p['condition'] as String?;
        _language = p['preferred_language'] as String?;
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
        condition: _condition!,
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
                          ConditionField(
                            value: _condition,
                            enabled: !_busy,
                            onChanged: (v) => setState(() => _condition = v),
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
