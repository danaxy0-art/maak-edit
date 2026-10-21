part of 'admin.dart';

// Admin account moderation: list and search accounts, view details and
// history, block with a reason, and reactivate. The server enforces every
// rule (admin-only, no self/admin blocks); this UI only explains them.

enum _AccountFilter { all, active, blocked }

/// Outcome of a block/reactivate dialog: the action succeeded, or another
/// administrator changed the account first and the page must refresh.
typedef ModerationOutcome = ({bool stale, String? text});

typedef _AccountsData = ({
  List<Map<String, dynamic>> rows,
  // Null when the appeals migration is not installed: appeal UI is hidden.
  List<Map<String, dynamic>>? pendingAppeals,
});

// Help seekers and volunteers (the server never returns admins), merged with
// their current block details and any pending appeal.
Future<_AccountsData> _fetchAccounts() async {
  final result = await Future.wait<Object?>([
    SupabaseService.getAccounts(),
    SupabaseService.getBlockedAccounts(),
    SupabaseService.getPendingAppeals(),
  ]).timeout(const Duration(seconds: 15));
  final blocks = {
    for (final b in result[1] as List<Map<String, dynamic>>) b['user_id']: b,
  };
  final appeals = result[2] as List<Map<String, dynamic>>?;
  final pending = {for (final a in appeals ?? const []) a['user_id']: a};
  return (
    rows: [
      for (final account in result[0] as List<Map<String, dynamic>>)
        {
          ...account,
          'block': blocks[account['user_id']],
          'pending_appeal': pending[account['user_id']],
        },
    ],
    pendingAppeals: appeals,
  );
}

class AccountsAdminPage extends StatefulWidget {
  const AccountsAdminPage({super.key});
  @override
  State<AccountsAdminPage> createState() => _AccountsAdminPageState();
}

class _AccountsAdminPageState extends State<AccountsAdminPage> {
  final _searchController = TextEditingController();
  String _search = '';
  _AccountFilter _filter = _AccountFilter.all;
  // Rows stay visible while a refresh runs; only the first load shows a spinner.
  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>>? _pendingAppeals;
  Object? _error;
  bool _loading = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final data = await _fetchAccounts();
      if (mounted) {
        setState(() {
          _rows = data.rows;
          _pendingAppeals = data.pendingAppeals;
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('Admin accounts load failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // No automatic background retry: errors wait for Try again or a pull.
  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch();
  }

  // Applied as soon as the detail page reports a change, so the status chip
  // and filter counts are right before the server refresh completes.
  void _applyChange(Map<String, dynamic> account) {
    final rows = _rows;
    if (rows == null) return;
    setState(() {
      _rows = [
        for (final row in rows)
          row['user_id'] == account['user_id'] ? account : row,
      ];
    });
  }

  Future<void> _open(Map<String, dynamic> account) async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AccountDetailPage(account: account, onChanged: _applyChange),
        ),
      );
    } finally {
      _opening = false;
    }
    if (mounted) _reload();
  }

  Future<void> _openAppeals() async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AppealsAdminPage()),
      );
    } finally {
      _opening = false;
    }
    if (mounted) _reload();
  }

  bool _matches(Map<String, dynamic> row) {
    final blocked = row['is_blocked'] == true;
    if (_filter == _AccountFilter.active && blocked) return false;
    if (_filter == _AccountFilter.blocked && !blocked) return false;
    if (_search.isEmpty) return true;
    return [
      _accountName(row),
      row['email'],
      row['username'],
      _roleLabel(row['role'] as String?),
    ].any((v) => (v as String? ?? '').toLowerCase().contains(_search));
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Accounts')),
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
                hintText: 'Search by name, email or username...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    ),
  );

  Widget _body() {
    final all = _rows;
    if (all == null) {
      if (_error != null) {
        return EmptyState(
          'Could not load accounts',
          friendlyError(_error!),
          retry: _reload,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final blockedCount = all.where((r) => r['is_blocked'] == true).length;
    final rows = all.where(_matches).toList();
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two columns on tablets, one on phones.
          final wide = constraints.maxWidth >= 680;
          final cardWidth = wide
              ? (constraints.maxWidth - 40 - 14) / 2
              : constraints.maxWidth - 40;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (_pendingAppeals != null) ...[
                _AppealsEntryCard(
                  pending: _pendingAppeals!.length,
                  onTap: _openAppeals,
                ),
                const SizedBox(height: 14),
              ],
              _filters(all.length, all.length - blockedCount, blockedCount),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _RefreshFailedNotice(error: _error!, retry: _reload),
              ],
              const SizedBox(height: 16),
              if (rows.isEmpty) _emptyState(all.isEmpty),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final row in rows)
                    SizedBox(
                      width: cardWidth,
                      child: _AccountCard(
                        account: row,
                        onTap: () => _open(row),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(bool noAccounts) {
    if (noAccounts) {
      return const EmptyState(
        'No accounts yet',
        'Registered members will appear here.',
      );
    }
    if (_search.isNotEmpty) {
      return const EmptyState(
        'No matching accounts',
        'Try a different search or filter.',
      );
    }
    return _filter == _AccountFilter.blocked
        ? const EmptyState(
            'No blocked accounts',
            'Blocked accounts will appear here.',
          )
        : const EmptyState(
            'No active accounts',
            'Active accounts will appear here.',
          );
  }

  Widget _filters(int all, int active, int blocked) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<_AccountFilter>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: _AccountFilter.all,
          label: _FilterLabel('All ($all)'),
        ),
        ButtonSegment(
          value: _AccountFilter.active,
          label: _FilterLabel('Active ($active)'),
        ),
        ButtonSegment(
          value: _AccountFilter.blocked,
          label: _FilterLabel('Blocked ($blocked)'),
        ),
      ],
      selected: {_filter},
      onSelectionChanged: (value) => setState(() => _filter = value.first),
    ),
  );
}

// Shrinks rather than overflows on small phones with large text.
class _FilterLabel extends StatelessWidget {
  final String text;
  const _FilterLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
}

class _RefreshFailedNotice extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const _RefreshFailedNotice({required this.error, required this.retry});

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Could not refresh. ${friendlyError(error)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        TextButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}

class _AccountCard extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback onTap;
  const _AccountCard({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final blocked = account['is_blocked'] == true;
    final block = account['block'] as Map?;
    final reason = (block?['reason'] as String? ?? '').trim();
    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.selectedCardFill,
            child: Text(initials(_accountName(account))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _accountName(account),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  account['email'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _AccountStatusChip(blocked: blocked),
                    RoleChip(_roleLabel(account['role'] as String?)),
                    if (account['pending_appeal'] != null)
                      const RoleChip('Appeal pending'),
                  ],
                ),
                // A two-line preview; the full reason is on the detail page.
                if (blocked && reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Blocked ${formatDay(block?['blocked_at'] as String?)}: $reason',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class AccountDetailPage extends StatefulWidget {
  final Map<String, dynamic> account;

  /// Called with the account's new state after each block or reactivation.
  final ValueChanged<Map<String, dynamic>>? onChanged;
  const AccountDetailPage({super.key, required this.account, this.onChanged});
  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  late Map<String, dynamic> _account = Map.of(widget.account);
  late Future<List<Map<String, dynamic>>> _history = _fetchHistory();
  bool _acting = false;
  bool _refreshing = false;
  bool _missing = false;
  String? _notice;
  // After a block, "Blocked on" and "Blocked by" wait for the server values
  // instead of showing an assumed identity or the device clock.
  bool _awaitingDetails = false;
  bool _detailsUnavailable = false;

  String get _id => _account['user_id'] as String? ?? '';
  String get _name => _accountName(_account);
  bool get _blocked => _account['is_blocked'] == true;

  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    try {
      return await SupabaseService.getModerationHistory(
        _id,
      ).timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('Moderation history load failed: ${error.runtimeType}');
      rethrow;
    }
  }

  // Reloads this account and its history from the server after an action, so
  // "Blocked by", "Times blocked" and the history show the stored values.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final data = await _fetchAccounts();
      final latest = data.rows.where((r) => r['user_id'] == _id).firstOrNull;
      if (!mounted) return;
      setState(() {
        if (latest == null) {
          _missing = true;
        } else {
          _account = latest;
        }
        _awaitingDetails = false;
        _detailsUnavailable = false;
        _history = _fetchHistory();
      });
      if (latest != null) widget.onChanged?.call(latest);
    } catch (error) {
      debugPrint('Account refresh failed: ${error.runtimeType}');
      if (mounted) {
        setState(() {
          _detailsUnavailable = _awaitingDetails;
          _notice =
              'The latest status could not be loaded. ${friendlyError(error)}';
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // Why no action is offered, or null when Block/Reactivate applies.
  String? get _noActionReason {
    if (_id.trim().isEmpty) {
      return 'This account has no ID. Return to the list and refresh it.';
    }
    if (_account['role'] == 'admin') {
      return 'Administrator accounts cannot be blocked.';
    }
    if (_id == SupabaseService.currentUser?.id) {
      return 'You cannot block your own account.';
    }
    return null;
  }

  Future<void> _moderate({required bool block}) async {
    if (_acting || _refreshing) return;
    setState(() {
      _acting = true;
      _notice = null;
    });
    try {
      final email = _account['email'] as String?;
      final outcome = await showDialog<ModerationOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => block
            ? BlockAccountDialog(userId: _id, name: _name, email: email)
            : ReactivateAccountDialog(userId: _id, name: _name, email: email),
      );
      if (!mounted || outcome == null) return;
      if (outcome.stale) {
        setState(
          () => _notice =
              'Another administrator changed this account. Its latest status is shown.',
        );
      } else {
        // Show the new status and the reason the admin typed at once. The
        // date and blocking admin are filled in by the refresh below from
        // the stored values, never assumed here.
        final updated = {
          ..._account,
          'is_blocked': block,
          'blocked_at': null,
          'pending_appeal': null,
          'block': block ? {'user_id': _id, 'reason': outcome.text} : null,
        };
        setState(() {
          _account = updated;
          _awaitingDetails = block;
          _detailsUnavailable = false;
        });
        widget.onChanged?.call(updated);
        showSuccess(
          context,
          block
              ? 'Account blocked successfully.'
              : 'Account reactivated successfully.',
        );
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    final block = a['block'] as Map?;
    final information = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow('Email', a['email'] as String?),
          _InfoRow('Username', a['username'] as String?),
          _InfoRow('Role', _roleLabel(a['role'] as String?)),
          if (a['volunteer_status'] != null)
            _InfoRow(
              'Volunteer application',
              _statusLabel(a['volunteer_status'] as String?),
            ),
          _InfoRow('Joined', formatDay(a['created_at'] as String?)),
        ],
      ),
    );
    final blocking = !_blocked || block == null
        ? null
        : SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow('Reason', block['reason'] as String?),
                _InfoRow(
                  'Blocked on',
                  _serverDetail(formatDay(block['blocked_at'] as String?)),
                ),
                _InfoRow('Blocked by', _serverDetail(_blockedByLabel(block))),
                if ((block['times_blocked'] as num? ?? 0) > 1)
                  _InfoRow('Times blocked', '${block['times_blocked']}'),
              ],
            ),
          );
    return BotanicalScaffold(
      appBar: AppBar(title: const Text('Account details')),
      body: _AdminResponsiveBody(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Information and blocking details side by side on tablets.
            final wide = constraints.maxWidth >= 680 && blocking != null;
            final pending = a['pending_appeal'] as Map<String, dynamic>?;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.selectedCardFill,
                        child: Text(initials(_name)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _name,
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _AccountStatusChip(blocked: _blocked),
                      RoleChip(_roleLabel(a['role'] as String?)),
                    ],
                  ),
                  if (pending != null && _blocked) ...[
                    const SizedBox(height: 16),
                    _PendingAppealBanner(
                      appeal: pending,
                      onReview: _acting || _refreshing
                          ? null
                          : () => _reviewAppeal(pending),
                    ),
                  ],
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionTitle('Account information'),
                              information,
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionTitle('Blocking details'),
                              blocking,
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    const SectionTitle('Account information'),
                    information,
                    if (blocking != null) ...[
                      const SectionTitle('Blocking details'),
                      blocking,
                    ],
                  ],
                  const SectionTitle('Moderation history'),
                  _historySection(),
                  const SizedBox(height: 28),
                  if (_notice != null) ...[
                    _InfoNotice(_notice!),
                    const SizedBox(height: 14),
                  ],
                  _actions(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Label for "Blocked on" / "Blocked by" until the server values arrive.
  String _serverDetail(String value) {
    if (_awaitingDetails || value.trim().isEmpty) {
      return _detailsUnavailable
          ? 'Unavailable — pull down to refresh'
          : 'Updating details…';
    }
    return value;
  }

  // The server's verified label; "(you)" only when the stored blocker UUID is
  // the signed-in admin, as reported by blocked_by_is_me.
  String _blockedByLabel(Map block) {
    final name = (block['blocked_by_name'] as String? ?? '').trim();
    if (name.isEmpty) return '';
    return block['blocked_by_is_me'] == true ? '$name (you)' : name;
  }

  Future<void> _reviewAppeal(Map<String, dynamic> appeal) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AppealDetailPage(appeal: appeal)),
    );
    if (mounted) await _refresh();
  }

  // Exactly one of: Block (active), Reactivate (blocked), or an explanation.
  Widget _actions() {
    if (_missing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldErrorNotice('This account no longer exists.'),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Return to accounts'),
          ),
        ],
      );
    }
    final reason = _noActionReason;
    if (reason != null) return _InfoNotice(reason);
    final enabled = !_acting && !_refreshing;
    if (_blocked) {
      return PrimaryButton(
        'Reactivate account',
        icon: Icons.lock_open,
        // Disabled, not spinning, while the dialog shows progress.
        onPressed: enabled ? () => _moderate(block: false) : null,
      );
    }
    return OutlinedButton.icon(
      onPressed: enabled ? () => _moderate(block: true) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
      ),
      icon: const Icon(Icons.block),
      label: const Text('Block account'),
    );
  }

  Widget _historySection() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _history,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return EmptyState(
          'Could not load history',
          friendlyError(snapshot.error!),
          retry: () => setState(() {
            _history = _fetchHistory();
          }),
        );
      }
      final events = snapshot.data ?? const [];
      if (events.isEmpty) {
        return const SurfaceCard(
          child: Text(
            'No moderation actions yet.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        );
      }
      // Kept in the server's order: newest first.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Newest first',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HistoryEntry(event),
            ),
        ],
      );
    },
  );
}

class _InfoNotice extends StatelessWidget {
  final String text;
  const _InfoNotice(this.text);

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: AppColors.primaryNavy),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _HistoryEntry extends StatelessWidget {
  final Map<String, dynamic> event;
  const _HistoryEntry(this.event);

  @override
  Widget build(BuildContext context) {
    final attempt = event['attempt'];
    // Actions from account_moderation_events and, with 20261023, appeals.
    final (title, icon, color) = switch (event['action']) {
      'blocked' => ('Blocked', Icons.block, AppColors.error),
      'reactivated' => (
        'Reactivated',
        Icons.check_circle_outline,
        AppColors.success,
      ),
      'appeal_submitted' => (
        'Appeal $attempt submitted',
        Icons.rate_review_outlined,
        AppColors.primaryNavy,
      ),
      'appeal_approved' => (
        'Appeal $attempt approved',
        Icons.thumb_up_alt_outlined,
        AppColors.success,
      ),
      'appeal_rejected' => (
        'Appeal $attempt rejected',
        Icons.thumb_down_alt_outlined,
        AppColors.error,
      ),
      'appeal_closed' => (
        'Appeal $attempt closed',
        Icons.do_not_disturb_on_outlined,
        AppColors.textMuted,
      ),
      _ => ('Moderation update', Icons.history, AppColors.textMuted),
    };
    final name = (event['actor_name'] as String? ?? '').trim();
    final by = name.isEmpty
        ? null
        : event['actor_is_me'] == true
        ? '$name (you)'
        : name;
    // Free text is shown as plain text only. Redacted appeal text and closed
    // appeals get an explanation instead.
    final reason = switch (event) {
      {'redacted': true} => 'Explanation removed when the account was deleted.',
      {'closed_reason': 'reactivated'} =>
        'Closed because the account was reactivated.',
      {'closed_reason': 'account_deleted'} =>
        'Closed because the account was deleted.',
      _ => (event['reason'] as String? ?? '').trim(),
    };
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    formatDay(event['created_at'] as String?),
                    if (by != null) 'by $by',
                  ].join(' '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(reason, style: const TextStyle(height: 1.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 3),
        Text(
          (value ?? '').trim().isEmpty ? 'Not provided' : value!,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
        ),
      ],
    ),
  );
}

/// The account a dialog acts on, shown before the admin confirms.
class _DialogAccount extends StatelessWidget {
  final String name;
  final String? email;
  const _DialogAccount({required this.name, this.email});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.selectedCardFill,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white,
          child: Text(initials(name), style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if ((email ?? '').isNotEmpty)
                Text(
                  email!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Shared shell for both moderation dialogs: account summary first, then the
/// form, with Cancel/confirm buttons. Scrolls when the keyboard is open.
class _ModerationDialog extends StatelessWidget {
  final String title, message, name, confirm, busyConfirm;
  final String? email, error;
  final bool busy, destructive;
  final GlobalKey<FormState> form;
  final Widget field;
  final VoidCallback onConfirm;
  const _ModerationDialog({
    required this.title,
    required this.message,
    required this.name,
    required this.email,
    required this.confirm,
    required this.busyConfirm,
    required this.busy,
    required this.destructive,
    required this.form,
    required this.field,
    required this.error,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Form(
        key: form,
        autovalidateMode: AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogAccount(name: name, email: email),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            field,
            if (error != null) FieldErrorNotice(error!),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : onConfirm,
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          child: Text(busy ? busyConfirm : confirm),
        ),
      ],
    ),
  );
}

/// Confirms a block and collects its required reason, validated inline.
class BlockAccountDialog extends StatefulWidget {
  final String userId;
  final String name;
  final String? email;
  const BlockAccountDialog({
    super.key,
    required this.userId,
    required this.name,
    this.email,
  });
  @override
  State<BlockAccountDialog> createState() => _BlockAccountDialogState();
}

class _BlockAccountDialogState extends State<BlockAccountDialog> {
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
    // _busy is set synchronously, so a second tap cannot send a second request.
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.blockAccount(
        userId: widget.userId,
        reason: _reason.text,
      );
      if (mounted) {
        Navigator.pop<ModerationOutcome>(context, (
          stale: false,
          text: _reason.text.trim(),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      if (_isStale(e, const [
        'already_blocked',
        'account_not_found',
        'cannot_block_admin',
      ])) {
        Navigator.pop<ModerationOutcome>(context, (stale: true, text: null));
      } else {
        // Network and other failures stay in the dialog; confirm again to retry.
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _ModerationDialog(
    title: 'Block account',
    message:
        'This account will lose access to support, messages and sessions until an administrator reactivates it. The member will see this reason.',
    name: widget.name,
    email: widget.email,
    confirm: 'Block account',
    busyConfirm: 'Blocking...',
    busy: _busy,
    destructive: true,
    form: _form,
    error: _error,
    onConfirm: _save,
    field: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Reason for blocking', requiredField: true),
        _AdminTextField(
          controller: _reason,
          maxLines: 4,
          maxLength: 500,
          enabled: !_busy,
          validator: validateBlockReason,
          decoration: const InputDecoration(
            hintText: 'Explain why this account is being blocked',
          ),
        ),
      ],
    ),
  );
}

/// Confirms a reactivation, with an optional note for the history.
class ReactivateAccountDialog extends StatefulWidget {
  final String userId;
  final String name;
  final String? email;
  const ReactivateAccountDialog({
    super.key,
    required this.userId,
    required this.name,
    this.email,
  });
  @override
  State<ReactivateAccountDialog> createState() =>
      _ReactivateAccountDialogState();
}

class _ReactivateAccountDialogState extends State<ReactivateAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.reactivateAccount(
        userId: widget.userId,
        note: _note.text,
      );
      if (mounted) {
        Navigator.pop<ModerationOutcome>(context, (
          stale: false,
          text: _note.text.trim(),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      if (_isStale(e, const ['not_blocked', 'account_not_found'])) {
        Navigator.pop<ModerationOutcome>(context, (stale: true, text: null));
      } else {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _ModerationDialog(
    title: 'Reactivate account',
    message:
        "This account will regain access to Ma'ak immediately. The moderation history is kept.",
    name: widget.name,
    email: widget.email,
    confirm: 'Reactivate account',
    busyConfirm: 'Reactivating...',
    busy: _busy,
    destructive: false,
    form: _form,
    error: _error,
    onConfirm: _save,
    field: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Note (optional)'),
        _AdminTextField(
          controller: _note,
          maxLines: 3,
          maxLength: 500,
          enabled: !_busy,
          validator: validateReactivationNote,
          decoration: const InputDecoration(
            hintText: 'Add a note for the moderation history',
          ),
        ),
      ],
    ),
  );
}

bool _isStale(Object error, List<String> codes) =>
    error is PostgrestException && codes.any(error.message.contains);

class _AccountStatusChip extends StatelessWidget {
  final bool blocked;
  const _AccountStatusChip({required this.blocked});

  @override
  Widget build(BuildContext context) {
    if (blocked) return const RoleChip('Blocked', error: true);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'Active',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
        ),
      ),
    );
  }
}

String _accountName(Map<String, dynamic> row) {
  final name = (row['full_name'] as String? ?? '').trim();
  if (name.isNotEmpty) return name;
  final username = (row['username'] as String? ?? '').trim();
  return username.isNotEmpty ? username : "Ma'ak member";
}

String _roleLabel(String? role) => role == 'help_seeker'
    ? 'Help seeker'
    : role == 'volunteer'
    ? 'Volunteer'
    : role == 'admin'
    ? 'Administrator'
    : 'Unknown role';
