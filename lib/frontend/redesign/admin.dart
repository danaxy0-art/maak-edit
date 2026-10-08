import 'app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../theme/app_theme.dart';
import '../widgets/maak_bottom_nav.dart';
import 'ui.dart';
import 'support.dart';
import 'profile.dart';
import 'feedback.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final _navigator = GlobalKey<NavigatorState>();
  int _index = 0;
  Widget _page(int index) => index == 1
      ? const ApplicationsPage()
      : index == 2
      ? const ConditionsAdminPage()
      : AdminOverview(select: _select);
  void _select(int index) {
    setState(() => _index = index);
    _navigator.currentState!.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _page(index)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    body: NavigatorPopHandler(
      onPopWithResult: (_) => _navigator.currentState!.pop(),
      child: Navigator(
        key: _navigator,
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _page(0)),
      ),
    ),
    bottomNavigationBar: MaakBottomNav(
      currentIndex: _index,
      onTap: _select,
      items: const [
        MaakNavItem(icon: Icons.home_outlined, label: 'Overview'),
        MaakNavItem(icon: Icons.description_outlined, label: 'Applications'),
        MaakNavItem(icon: Icons.favorite_border, label: 'Conditions'),
      ],
    ),
  );
}

class AdminOverview extends StatefulWidget {
  final ValueChanged<int> select;
  const AdminOverview({super.key, required this.select});
  @override
  State<AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<AdminOverview> {
  late Future<List<List<Map<String, dynamic>>>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = Future.wait([
    SupabaseService.getVolunteerApplications(),
    SupabaseService.getConditions(activeOnly: false),
  ]);
  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    body: SafeArea(
      child: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LogoHeader(
              trailing: IconButton(
                tooltip: 'Log out',
                onPressed: () => logout(context),
                icon: const Icon(Icons.logout),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Admin overview',
              style: TextStyle(
                fontFamily: 'MaakSerif',
                fontSize: 27,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage volunteer applications and chronic conditions.',
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 26),
            FutureBuilder<List<List<Map<String, dynamic>>>>(
              future: _future,
              builder: (context, s) {
                if (s.hasError) {
                  return EmptyState(
                    'Could not load overview',
                    friendlyError(s.error!),
                    retry: () => setState(_load),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final applications = s.data![0], conditions = s.data![1];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _stat(
                          'Pending applications',
                          applications
                              .where((r) => r['status'] == 'pending_review')
                              .length,
                          Icons.people_outline,
                        ),
                        const SizedBox(width: 14),
                        _stat(
                          'Active conditions',
                          conditions
                              .where((r) => r['is_active'] == true)
                              .length,
                          Icons.favorite,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _menu(
                      'Volunteer applications',
                      'Review pending applications',
                      Icons.description_outlined,
                      () => widget.select(1),
                    ),
                    const SizedBox(height: 14),
                    _menu(
                      'Chronic conditions',
                      'Manage condition types',
                      Icons.favorite_border,
                      () => widget.select(2),
                    ),
                    const SectionTitle('Latest applications'),
                    if (applications.isEmpty)
                      const EmptyState(
                        'No applications yet',
                        'New volunteer applications will appear here.',
                      ),
                    for (final row in applications.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SurfaceCard(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ApplicationDetailPage(application: row),
                              ),
                            );
                            if (mounted) setState(_load);
                          },
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.selectedCardFill,
                                child: Text(initials(_appName(row))),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  _appName(row),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              RoleChip(
                                _statusLabel(row['status'] as String),
                                error: row['status'] == 'rejected',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
  Widget _stat(String text, int count, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.selectedCardFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: AppColors.primaryNavy),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 9),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'MaakSerif',
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _menu(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => SurfaceCard(
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, size: 32, color: AppColors.primaryNavy),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

class ApplicationsPage extends StatelessWidget {
  const ApplicationsPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Volunteer applications',
    load: SupabaseService.getVolunteerApplications,
    emptyTitle: 'No applications yet',
    emptyText: 'Submitted applications will appear here.',
    item: (context, row, refresh) => SurfaceCard(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ApplicationDetailPage(application: row),
          ),
        );
        refresh();
      },
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.selectedCardFill,
            child: Text(initials(_appName(row))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _appName(row),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  row['condition_experience'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                RoleChip(
                  _statusLabel(row['status'] as String),
                  error: row['status'] == 'rejected',
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}

class ConditionsAdminPage extends StatefulWidget {
  const ConditionsAdminPage({super.key});
  @override
  State<ConditionsAdminPage> createState() => _ConditionsAdminPageState();
}

class _ConditionsAdminPageState extends State<ConditionsAdminPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String _search = '';
  final Set<String> _saving = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = SupabaseService.getConditions(activeOnly: false);
  Future<void> _edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ConditionDialog(condition: row),
    );
    if (saved == true && mounted) setState(_load);
  }

  Future<void> _toggle(Map<String, dynamic> row, bool active) async {
    final id = row['id'] as String;
    setState(() => _saving.add(id));
    try {
      await SupabaseService.saveCondition(
        id: id,
        name: row['name'] as String,
        active: active,
      );
      if (mounted) setState(_load);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Chronic conditions')),
    body: ResponsiveBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Manage the conditions available during registration.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 18),
                TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search conditions...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  'Add condition',
                  icon: Icons.add,
                  onPressed: _edit,
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, s) {
                if (s.hasError) {
                  return EmptyState(
                    'Could not load conditions',
                    friendlyError(s.error!),
                    retry: () => setState(_load),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = s.data!
                    .where(
                      (r) =>
                          (r['name'] as String).toLowerCase().contains(_search),
                    )
                    .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SurfaceCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.favorite_border,
                                color: row['is_active'] == true
                                    ? AppColors.selectedCardBorder
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['name'] as String,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      row['is_active'] == true
                                          ? 'Active'
                                          : 'Inactive',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: row['is_active'] as bool,
                                onChanged: _saving.contains(row['id'])
                                    ? null
                                    : (v) => _toggle(row, v),
                              ),
                              IconButton(
                                tooltip: 'Edit condition',
                                onPressed: _saving.contains(row['id'])
                                    ? null
                                    : () => _edit(row),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (rows.isEmpty)
                      const EmptyState(
                        'No matching conditions',
                        'Try a different search.',
                      ),
                    const SizedBox(height: 14),
                    const SurfaceCard(
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 19),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Active conditions appear in registration. Disabling keeps existing profiles intact.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConditionDialog extends StatefulWidget {
  final Map<String, dynamic>? condition;
  const _ConditionDialog({this.condition});
  @override
  State<_ConditionDialog> createState() => _ConditionDialogState();
}

class _ConditionDialogState extends State<_ConditionDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.condition?['name'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.saveCondition(
        id: widget.condition?['id'] as String?,
        name: _name.text,
        active: widget.condition?['is_active'] as bool? ?? true,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.condition == null ? 'Add condition' : 'Edit condition',
      ),
      content: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Condition name', requiredField: true),
            AppTextField(
              controller: _name,
              enabled: !_busy,
              maxLength: 80,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter a condition name'
                  : null,
            ),
            if (_error != null) FieldErrorNotice(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving...' : 'Save'),
        ),
      ],
    ),
  );
}

class ApplicationDetailPage extends StatefulWidget {
  final Map<String, dynamic> application;
  const ApplicationDetailPage({super.key, required this.application});
  @override
  State<ApplicationDetailPage> createState() => _ApplicationDetailPageState();
}

class _ApplicationDetailPageState extends State<ApplicationDetailPage> {
  bool _busy = false;
  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await SupabaseService.approveVolunteerApplication(
        widget.application['user_id'] as String,
      );

      try {
  final profile = widget.application['profiles'] as Map?;

  await SupabaseService.sendVolunteerEmail(
    email: profile?['email'] as String? ?? '',
    name: profile?['full_name'] as String? ?? 'Volunteer',
    status: 'approved',
  );
} catch (e) {
  debugPrint('Volunteer approval email failed: $e');
}

      if (mounted) {
                showSuccess( context,
          'Volunteer application approved successfully.',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
  final profile = widget.application['profiles'] as Map?;

  return RejectApplicationDialog(
    userId: widget.application['user_id'] as String,
    email: profile?['email'] as String? ?? '',
    name: profile?['full_name'] as String? ?? 'Volunteer',
  );
},
    );
    if (saved == true && mounted) {
          showSuccess( context,
      'Volunteer application rejected successfully.',
    );
          Navigator.pop(context);
    }
  }

  Future<void> _document(String value) async {
    try {
      final url = await SupabaseService.verificationLink(value);
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Could not open document');
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.application;
    return BotanicalScaffold(
      appBar: AppBar(title: const Text('Application details')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.selectedCardFill,
                  child: Text(initials(_appName(a))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _appName(a),
                    style: const TextStyle(
                      fontFamily: 'MaakSerif',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: RoleChip(
                _statusLabel(a['status'] as String),
                error: a['status'] == 'rejected',
              ),
            ),
            const SectionTitle('Personal information'),
            SurfaceCard(
              child: Text(
                'Condition: ${a['condition_experience']}\nLanguage: ${a['preferred_language']}',
                style: const TextStyle(height: 1.9),
              ),
            ),
            const SectionTitle('Lived experience'),
            SurfaceCard(
              child: Text(
                a['experience_description'] as String? ?? '',
                style: const TextStyle(height: 1.6),
              ),
            ),
            const SectionTitle('Verification document'),
            if ((a['verification_document_url'] as String? ?? '').isNotEmpty)
              OutlinedButton.icon(
                onPressed: () =>
                    _document(a['verification_document_url'] as String),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open document'),
              )
            else
              const Text('No document uploaded'),
            if (a['status'] == 'rejected') ...[
              const SectionTitle('Reason for rejection'),
              SurfaceCard(child: Text(a['rejection_reason'] as String? ?? '')),
            ],
            const SizedBox(height: 32),
            if (a['status'] == 'pending_review')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _reject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      'Approve',
                      busy: _busy,
                      onPressed: _approve,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class RejectApplicationDialog extends StatefulWidget {
  final String userId;
  final String email;
  final String name;

  const RejectApplicationDialog({
    super.key,
    required this.userId,
    required this.email,
    required this.name,
  });

  @override
  State<RejectApplicationDialog> createState() =>
      _RejectApplicationDialogState();
}


class _RejectApplicationDialogState extends State<RejectApplicationDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.rejectVolunteerApplication(
        userId: widget.userId,
        reason: _reason.text,
      );

      try {
  await SupabaseService.sendVolunteerEmail(
    email: widget.email,
    name: widget.name,
    status: 'rejected',
    rejectionReason: _reason.text,
  );
} catch (e) {
  debugPrint('Volunteer rejection email failed: $e');
}
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Reject application'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tell the volunteer what needs to be corrected.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
              const FieldLabel('Reason', requiredField: true),
              AppTextField(
                controller: _reason,
                maxLines: 4,
                maxLength: 500,
                enabled: !_busy,
                validator: validateReason,
                decoration: const InputDecoration(
                  hintText: 'Enter the reason for rejection',
                ),
              ),
              if (_error != null) FieldErrorNotice(_error!),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: Text(_busy ? 'Saving...' : 'Reject'),
        ),
      ],
    ),
  );
}

String _appName(Map<String, dynamic> row) =>
    (row['profiles'] as Map?)?['full_name'] as String? ?? 'Volunteer';
String _statusLabel(String status) => status == 'pending_review'
    ? 'Pending'
    : status == 'approved'
    ? 'Approved'
    : 'Rejected';
