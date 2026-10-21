import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../theme/app_theme.dart';
import '../widgets/maak_bottom_nav.dart';
import 'ui.dart';
import 'app_text_field.dart';
import 'profile.dart';
import 'feedback.dart';
import 'condition_reviews.dart';

// Admin layouts use a wider content area on tablets while preserving
// Ma'ak's existing theme, bottom navigation, and phone widths.
class _AdminResponsiveBody extends StatelessWidget {
  final Widget child;
  const _AdminResponsiveBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width >= 900
        ? 960.0
        : width >= 600
        ? 720.0
        : 520.0;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

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

  // Failed requests stay on the error screen until the Admin retries.
  void _load() {
    _future = _loadOverview();
  }

  Future<List<List<Map<String, dynamic>>>> _loadOverview() async {
    try {
      final result = await Future.wait([
        SupabaseService.getVolunteerApplications(),
        SupabaseService.getConditions(activeOnly: false),
      ]).timeout(const Duration(seconds: 15));
      return result;
    } catch (error) {
      debugPrint('Admin overview load failed: ${error.runtimeType}');
      rethrow;
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("Are you sure you want to log out of Ma'ak?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await logout(context);
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    body: SafeArea(
      child: _AdminResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LogoHeader(
              trailing: IconButton(
                tooltip: 'Log out',
                onPressed: _confirmLogout,
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
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
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
                              _AdminStatusChip(row['status'] as String?),
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

class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key});

  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String _search = '';
  final _searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // No automatic background retry: leave the error and Try again visible.
  void _reload() {
    if (mounted) {
      setState(() {
        _future = _fetch();
      });
    } else {
      _future = _fetch();
    }
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    try {
      final rows = await SupabaseService.getVolunteerApplications().timeout(
        const Duration(seconds: 15),
      );
      return rows;
    } catch (error) {
      debugPrint('Admin applications load failed: ${error.runtimeType}');
      rethrow;
    }
  }

  Future<void> _pullToRefresh() async {
    _reload();
    try {
      await _future;
    } catch (_) {
      // FutureBuilder renders the team's standard retryable EmptyState.
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Volunteer applications')),
    body: _AdminResponsiveBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search applications...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return EmptyState(
                    'Could not load applications',
                    friendlyError(snapshot.error!),
                    retry: _reload,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!.where((row) {
                  if (_search.isEmpty) return true;
                  final name = _appName(row).toLowerCase();
                  final condition =
                      (row['condition_experience'] as String? ?? '')
                          .toLowerCase();
                  final status = _statusLabel(row['status'] as String?)
                      .toLowerCase();
                  return name.contains(_search) ||
                      condition.contains(_search) ||
                      status.contains(_search);
                }).toList();
                return RefreshIndicator(
                  onRefresh: _pullToRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (snapshot.data!.isEmpty)
                        const EmptyState(
                          'No applications yet',
                          'Submitted applications will appear here.',
                        ),
                      if (rows.isEmpty && snapshot.data!.isNotEmpty)
                        const EmptyState(
                          'No matching applications',
                          'Try a different search.',
                        ),
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: SurfaceCard(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ApplicationDetailPage(application: row),
                                ),
                              );
                              if (mounted) _reload();
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _appName(row),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        row['condition_experience']
                                                as String? ??
                                            '',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _AdminStatusChip(
                                        row['status'] as String?,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
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
  final _searchController = TextEditingController();
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    _future = _fetchConditions();
  }

  Future<List<Map<String, dynamic>>> _fetchConditions() async {
    try {
      final rows = await SupabaseService.getConditions(activeOnly: false)
          .timeout(const Duration(seconds: 15));
      return rows;
    } catch (error) {
      debugPrint('Admin conditions load failed: ${error.runtimeType}');
      rethrow;
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ConditionDialog(condition: row),
    );
    if (saved == true && mounted) {
      // An old search term can otherwise hide the newly edited/added row.
      _searchController.clear();
      setState(() {
        _search = '';
        _load();
      });
      showSuccess(context, 'Condition saved.');
    }
  }

  Future<void> _toggle(Map<String, dynamic> row, bool active) async {
    final id = row['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      showAppError(
        context,
        ArgumentError(
          'This condition has no ID. Refresh the list and try again.',
        ),
      );
      return;
    }
    setState(() => _saving.add(id));
    try {
      await SupabaseService.saveCondition(
        id: id,
        name: row['name'] as String,
        active: active,
      );
      // The write succeeded. Refresh separately, so a network failure while
      // reloading cannot be mistaken for a failed database update.
      if (mounted) {
        setState(_load);
        showSuccess(
          context,
          active ? 'Condition activated.' : 'Condition deactivated.',
        );
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Chronic conditions')),
    body: _AdminResponsiveBody(
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
                  controller: _searchController,
                  onChanged: (v) =>
                      setState(() => _search = v.trim().toLowerCase()),
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
                TextButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ConditionRequestsPage(),
                      ),
                    );
                    if (mounted) setState(_load);
                  },
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review Other condition requests'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
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
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(_load);
                    try {
                      await _future;
                    } catch (_) {
                      // The error is displayed by FutureBuilder.
                    }
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                  onPressed:
                                      _saving.contains(row['id']) ||
                                          row['is_other'] == true
                                      ? null
                                      : () => _edit(row),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                  ),
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
                  ),
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
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.condition != null &&
        (widget.condition!['id'] as String? ?? '').trim().isEmpty) {
      setState(
        () => _error =
            'This condition has no ID. Close this dialog and refresh the list.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.saveCondition(
        id: widget.condition?['id'] as String?,
        name: _name.text.trim(),
        active: widget.condition?['is_active'] as bool? ?? true,
      );
      // A successful save is not undone if refreshing the list fails.
      // The parent page reloads the list and handles any refresh error.
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
            _AdminTextField(
              controller: _name,
              enabled: !_busy,
              maxLength: 80,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter a condition name'
                  : v.trim().length > 80
                  ? 'Use at most 80 characters'
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
  bool _openingDocument = false;
  bool _rejecting = false;
  bool _stale = false;
  String? _decision;
  String? _notice;
  String? get _status => _decision ?? widget.application['status'] as String?;

  bool _canReview() {
    if (_busy || _rejecting || _stale || _status != 'pending_review') {
      return false;
    }
    if ((widget.application['user_id'] as String? ?? '').trim().isEmpty) {
      showAppError(
        context,
        ArgumentError(
          'This application has no volunteer ID. Return to the list and refresh it.',
        ),
      );
      return false;
    }
    return true;
  }

  void _reviewError(Object error) {
    if (error is PostgrestException &&
        error.message.contains('application_changed')) {
      setState(() {
        _stale = true;
        _notice = 'This application has changed. Return to the list to load its current status.';
      });
    }
    showAppError(context, error);
  }

  Future<void> _approve() async {
    if (!_canReview()) return;
    setState(() => _busy = true);
    try {
      final volunteerId = widget.application['user_id'] as String;
      await SupabaseService.approveVolunteerApplication(volunteerId);
      bool emailAccepted = false;
      try {
        // The server resolves the volunteer's address from the stored review.
        await SupabaseService.sendVolunteerEmail(
          status: 'approved',
          volunteerId: volunteerId,
        );
        emailAccepted = true;
      } catch (_) {
        // The review and in-app notification have already committed.
      }
      if (mounted) {
        _completeReview(
          'approved',
          emailAccepted: emailAccepted,
          emailFailed: !emailAccepted,
        );
      }
    } catch (e) {
      if (mounted) _reviewError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _completeReview(
    String status, {
    required bool emailAccepted,
    required bool emailFailed,
  }) {
    setState(() {
      _decision = status;
      // A failed optional email must not be presented as a failed review.
      _notice = emailFailed
          ? 'Decision saved successfully. The volunteer can see the updated status in the app. Email delivery is currently unavailable; do not repeat the decision.'
          : null;
    });
    showSuccess(
      context,
      status == 'approved'
          ? 'Application approved successfully.'
          : 'Application rejected successfully.',
    );
  }

  Future<void> _reject() async {
    if (!_canReview()) return;
    setState(() => _rejecting = true);
    try {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RejectApplicationDialog(
          userId: widget.application['user_id'] as String,
        ),
      );
      if (!mounted || result == null) return;
      if (result == 'stale') {
        setState(() {
          _stale = true;
          _notice = 'This application has changed. Return to the list to load its current status.';
        });
      } else {
        _completeReview(
          'rejected',
          emailAccepted: result == 'sent',
          emailFailed: result == 'email_failed',
        );
      }
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  Future<void> _document(String value) async {
    if (_openingDocument) return;
    setState(() => _openingDocument = true);
    try {
      if (value.trim().isEmpty) {
        throw ArgumentError(
          'No verification document is available. Return to the list and refresh it.',
        );
      }
      final url = await SupabaseService.verificationLink(value.trim());
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw ArgumentError(
          'Could not open the document. Check that a browser is available and try again.',
        );
      }
    } catch (e) {
      if (mounted) showAppError(context, e, retry: () => _document(value));
    } finally {
      if (mounted) setState(() => _openingDocument = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.application;
    return BotanicalScaffold(
      appBar: AppBar(title: const Text('Application details')),
      body: _AdminResponsiveBody(
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
              child: _AdminStatusChip(_status),
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
            if ((a['verification_document_url'] as String? ?? '')
                .trim()
                .isNotEmpty)
              OutlinedButton.icon(
                onPressed: _openingDocument
                    ? null
                    : () => _document(a['verification_document_url'] as String),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  _openingDocument ? 'Opening document...' : 'Open document',
                ),
              )
            else
              const FieldErrorNotice(
                'No verification document is available. Ask the volunteer for a document before approving.',
              ),
            if (a['status'] == 'rejected') ...[
              const SectionTitle('Reason for rejection'),
              SurfaceCard(child: Text(a['rejection_reason'] as String? ?? '')),
            ],
            const SizedBox(height: 32),
            if (_notice != null)
              _stale
                  ? FieldErrorNotice(_notice!)
                  : SurfaceCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.primaryNavy,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _notice!,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            if (_stale)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Return to applications'),
              ),
            if (_status == 'pending_review' && !_stale)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy || _rejecting ? null : _reject,
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
                      onPressed:
                          (_rejecting
                                  ? ''
                                  : a['verification_document_url'] as String? ??
                                        '')
                              .trim()
                              .isEmpty
                          ? null
                          : _approve,
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

  const RejectApplicationDialog({super.key, required this.userId});

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
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.userId.trim().isEmpty) {
      setState(
        () => _error = 'This application has no volunteer ID. Close this dialog and refresh the list.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.rejectVolunteerApplication(
        userId: widget.userId,
        reason: _reason.text,
      );

      bool emailAccepted = false;
      try {
        // The server reads the stored reason; no reason text is sent here.
        await SupabaseService.sendVolunteerEmail(
          status: 'rejected',
          volunteerId: widget.userId,
        );
        emailAccepted = true;
      } catch (_) {
        // Preserve the committed review even if the optional email fails.
      }
      if (mounted) {
        Navigator.pop(context, emailAccepted ? 'sent' : 'email_failed');
      }
    } catch (e) {
      if (mounted) {
        if (e is PostgrestException &&
            e.message.contains('application_changed')) {
          Navigator.pop(context, 'stale');
        } else {
          setState(() => _error = friendlyError(e));
        }
      }
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
              _AdminTextField(
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
          onPressed: _busy ? null : () => Navigator.pop(context),
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

// Reuse the team's RoleChip for Pending/Rejected; highlight Approved in
// the team's existing green success color without changing shared widgets.
class _AdminStatusChip extends StatelessWidget {
  final String? status;
  const _AdminStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    if (status != 'approved') {
      return RoleChip(_statusLabel(status), error: status == 'rejected');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'Approved',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
        ),
      ),
    );
  }
}

String _statusLabel(String? status) => status == 'pending_review'
    ? 'Pending'
    : status == 'approved'
    ? 'Approved'
    : status == 'rejected'
    ? 'Rejected'
    : 'Unknown status';

/// Admin-only form field: matches Ma'ak's inline red FieldErrorNotice and
/// red input border. It also displays errors on Save, even if never touched.
/// (The shared AppTextField currently hides untouched submit errors.)
class _AdminTextField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final int maxLength;
  final int maxLines;
  final FormFieldValidator<String> validator;
  final InputDecoration decoration;
  const _AdminTextField({
    required this.controller,
    required this.enabled,
    required this.maxLength,
    required this.validator,
    this.maxLines = 1,
    this.decoration = const InputDecoration(),
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
            onChanged: (value) {
              final hadError = field.hasError;
              field.didChange(value);
              if (hadError) field.validate();
            },
            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              field.didChange(controller.text);
              field.validate();
            },
            decoration: decoration.copyWith(
              enabledBorder: field.hasError
                  ? errorBorder
                  : decoration.enabledBorder,
              focusedBorder: field.hasError
                  ? errorBorder
                  : decoration.focusedBorder,
              suffixIcon: field.hasError
                  ? const Icon(Icons.error_outline, color: AppColors.error)
                  : decoration.suffixIcon,
            ),
          ),
        ],
      );
    },
  );
}
