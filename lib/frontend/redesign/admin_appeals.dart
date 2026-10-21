part of 'admin.dart';

// Admin review of account-restriction appeals (20261023_account_appeals.sql),
// inside Manage Accounts. The server enforces every rule: admin-only, at most
// three appeals per block, one pending, and a single decision per appeal.
// Member-written text is always shown as plain text.

/// Entry point on the Accounts page, in the style of the Overview cards.
class _AppealsEntryCard extends StatelessWidget {
  final int pending;
  final VoidCallback onTap;
  const _AppealsEntryCard({required this.pending, required this.onTap});

  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    child: Row(
      children: [
        const Icon(
          Icons.rate_review_outlined,
          size: 32,
          color: AppColors.primaryNavy,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Appeals',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                pending == 0
                    ? 'No pending appeals'
                    : pending == 1
                    ? '1 pending appeal'
                    : '$pending pending appeals',
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

/// Shown on Account details while the member has a pending appeal.
class _PendingAppealBanner extends StatelessWidget {
  final Map<String, dynamic> appeal;
  final VoidCallback? onReview;
  const _PendingAppealBanner({required this.appeal, required this.onReview});

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.rate_review_outlined,
              color: AppColors.primaryNavy,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pending appeal · attempt ${appeal['attempt']} of ${appeal['max_appeals'] ?? 3}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Submitted ${formatDay(appeal['submitted_at'] as String?)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Text(
          appeal['message'] as String? ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(height: 1.4),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onReview,
            child: const Text('Review appeal'),
          ),
        ),
      ],
    ),
  );
}

class AppealsAdminPage extends StatefulWidget {
  const AppealsAdminPage({super.key});
  @override
  State<AppealsAdminPage> createState() => _AppealsAdminPageState();
}

class _AppealsAdminPageState extends State<AppealsAdminPage> {
  final _searchController = TextEditingController();
  String _search = '';
  // Rows stay visible while a refresh runs; only the first load shows a spinner.
  List<Map<String, dynamic>>? _rows;
  Object? _error;
  bool _loading = true;
  bool _installed = true;
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
      final rows = await SupabaseService.getPendingAppeals().timeout(
        const Duration(seconds: 15),
      );
      if (mounted) {
        setState(() {
          _installed = rows != null;
          _rows = rows ?? const [];
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('Pending appeals load failed: ${error.runtimeType}');
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

  Future<void> _open(Map<String, dynamic> appeal) async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AppealDetailPage(appeal: appeal)),
      );
    } finally {
      _opening = false;
    }
    if (mounted) _reload();
  }

  bool _matches(Map<String, dynamic> row) =>
      _search.isEmpty ||
      [
        _accountName(row),
        row['email'],
        row['username'],
      ].any((v) => (v as String? ?? '').toLowerCase().contains(_search));

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Appeals')),
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
          'Could not load appeals',
          friendlyError(_error!),
          retry: _reload,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final rows = all.where(_matches).toList();
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          final cardWidth = wide
              ? (constraints.maxWidth - 40 - 14) / 2
              : constraints.maxWidth - 40;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (_installed)
                Text(
                  all.length == 1
                      ? '1 pending appeal'
                      : '${all.length} pending appeals',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _RefreshFailedNotice(error: _error!, retry: _reload),
              ],
              const SizedBox(height: 16),
              if (!_installed)
                const EmptyState(
                  'Appeals are not available yet',
                  'The appeals database update has not been installed.',
                )
              else if (all.isEmpty)
                const EmptyState(
                  'No pending appeals',
                  'Appeals from restricted members will appear here.',
                )
              else if (rows.isEmpty)
                const EmptyState(
                  'No matching appeals',
                  'Try a different search.',
                ),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final row in rows)
                    SizedBox(
                      width: cardWidth,
                      child: _PendingAppealCard(
                        appeal: row,
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
}

class _PendingAppealCard extends StatelessWidget {
  final Map<String, dynamic> appeal;
  final VoidCallback onTap;
  const _PendingAppealCard({required this.appeal, required this.onTap});

  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.selectedCardFill,
          child: Text(initials(_accountName(appeal))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _accountName(appeal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                appeal['email'] as String? ?? '',
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
                  RoleChip(_roleLabel(appeal['role'] as String?)),
                  RoleChip(
                    'Attempt ${appeal['attempt']} of ${appeal['max_appeals'] ?? 3}',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Submitted ${formatDay(appeal['submitted_at'] as String?)}: ${appeal['message'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

class AppealDetailPage extends StatefulWidget {
  /// A row from admin_pending_appeals().
  final Map<String, dynamic> appeal;
  const AppealDetailPage({super.key, required this.appeal});
  @override
  State<AppealDetailPage> createState() => _AppealDetailPageState();
}

class _AppealDetailPageState extends State<AppealDetailPage> {
  late Future<List<Map<String, dynamic>>?> _appeals = _fetchAppeals();
  late Future<List<Map<String, dynamic>>> _history = _fetchHistory();
  // Set once this admin decides, or when a refresh finds it already decided.
  String? _status;
  String? _notice;
  bool _acting = false;

  Map<String, dynamic> get _a => widget.appeal;
  String get _appealId => _a['appeal_id'] as String? ?? '';
  String get _userId => _a['user_id'] as String? ?? '';
  String get _name => _accountName(_a);
  bool get _pending => _status == null;

  Future<List<Map<String, dynamic>>?> _fetchAppeals() async {
    try {
      final rows = await SupabaseService.getAccountAppeals(
        _userId,
      ).timeout(const Duration(seconds: 15));
      // Another admin may have decided since the list loaded.
      final current = rows?.where((r) => r['appeal_id'] == _appealId);
      final status = current == null || current.isEmpty
          ? null
          : current.first['status'] as String?;
      if (mounted && _pending && status != null && status != 'pending') {
        setState(() {
          _status = status;
          _notice =
              'Another administrator has already reviewed this appeal. Its latest status is shown.';
        });
      }
      return rows;
    } catch (error) {
      debugPrint('Account appeals load failed: ${error.runtimeType}');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    try {
      return await SupabaseService.getModerationHistory(
        _userId,
      ).timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('Moderation history load failed: ${error.runtimeType}');
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _appeals = _fetchAppeals();
      _history = _fetchHistory();
    });
    try {
      await Future.wait([_appeals, _history]);
    } catch (_) {
      // Each section shows its own retryable error.
    }
  }

  Future<void> _decide({required bool approve}) async {
    if (_acting || !_pending) return;
    setState(() => _acting = true);
    try {
      final outcome = await showDialog<ModerationOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AppealDecisionDialog(
          appealId: _appealId,
          approve: approve,
          name: _name,
          email: _a['email'] as String?,
        ),
      );
      if (!mounted || outcome == null) return;
      if (outcome.stale) {
        setState(
          () => _notice =
              'Another administrator has already reviewed this appeal. Its latest status is shown.',
        );
      } else if (approve) {
        // Approval ends the restriction: confirm and return to the pending
        // list, which reloads on return and no longer includes this appeal.
        showSuccess(context, 'Appeal approved. Account reactivated.');
        Navigator.maybePop(context);
        return;
      } else {
        setState(() {
          _status = 'rejected';
          _notice = 'Appeal rejected. The account stays restricted.';
        });
        showSuccess(context, 'Appeal rejected.');
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appealCard = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow('Submitted', formatDay(_a['submitted_at'] as String?)),
          _InfoRow('Attempt', '${_a['attempt']} of ${_a['max_appeals'] ?? 3}'),
          const SizedBox(height: 6),
          const Text(
            'Explanation',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 3),
          Text(
            _a['message'] as String? ?? '',
            style: const TextStyle(height: 1.5),
          ),
        ],
      ),
    );
    final blockedBy = (_a['blocked_by_name'] as String? ?? '').trim();
    final restrictionCard = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow('Reason', _a['block_reason'] as String?),
          _InfoRow('Blocked on', formatDay(_a['blocked_at'] as String?)),
          _InfoRow(
            'Blocked by',
            _a['blocked_by_is_me'] == true && blockedBy.isNotEmpty
                ? '$blockedBy (you)'
                : blockedBy,
          ),
        ],
      ),
    );
    return BotanicalScaffold(
      appBar: AppBar(title: const Text('Appeal details')),
      body: _AdminResponsiveBody(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 680;
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _name,
                              style: const TextStyle(
                                fontFamily: 'MaakSerif',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _a['email'] as String? ?? '',
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
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      RoleChip(_roleLabel(_a['role'] as String?)),
                      _AppealDecisionChip(_status ?? 'pending'),
                    ],
                  ),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionTitle('Appeal'),
                              appealCard,
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionTitle('Original restriction'),
                              restrictionCard,
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    const SectionTitle('Appeal'),
                    appealCard,
                    const SectionTitle('Original restriction'),
                    restrictionCard,
                  ],
                  const SectionTitle('Earlier appeals for this restriction'),
                  _earlierAppeals(),
                  const SectionTitle('Moderation history'),
                  _historySection(),
                  const SizedBox(height: 28),
                  if (_notice != null) ...[
                    _InfoNotice(_notice!),
                    const SizedBox(height: 14),
                  ],
                  if (_pending)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _acting
                                ? null
                                : () => _decide(approve: false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                            ),
                            child: const Text('Reject appeal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            'Approve appeal',
                            onPressed: _acting
                                ? null
                                : () => _decide(approve: true),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _earlierAppeals() => FutureBuilder<List<Map<String, dynamic>>?>(
    future: _appeals,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return EmptyState(
          'Could not load earlier appeals',
          friendlyError(snapshot.error!),
          retry: () => setState(() {
            _appeals = _fetchAppeals();
          }),
        );
      }
      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
      // "This restriction" is this appeal's blocking event. is_current_block
      // cannot identify it: it turns false for every appeal once the block
      // ends, for example right after an approval.
      final blockEventId = rows
          .where((r) => r['appeal_id'] == _appealId)
          .firstOrNull?['block_event_id'];
      final earlier = rows
          .where(
            (r) =>
                r['appeal_id'] != _appealId &&
                (blockEventId != null
                    ? r['block_event_id'] == blockEventId
                    : r['is_current_block'] == true),
          )
          .toList();
      if (earlier.isEmpty) {
        return SurfaceCard(
          child: Text(
            (_a['attempt'] as num? ?? 1) <= 1
                ? 'This is the first appeal for this restriction.'
                : 'Earlier appeals for this restriction could not be loaded. Pull down to refresh.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
        );
      }
      return Column(
        children: [
          for (final r in earlier)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Appeal ${r['attempt']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _AppealDecisionChip(r['status'] as String?),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        'Submitted ${formatDay(r['submitted_at'] as String?)}',
                        if ((r['decided_by_name'] as String?) != null)
                          r['decided_by_is_me'] == true
                              ? 'decided by ${r['decided_by_name']} (you)'
                              : 'decided by ${r['decided_by_name']}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      r['message'] as String? ??
                          'Explanation removed when the account was deleted.',
                      style: const TextStyle(height: 1.5),
                    ),
                    if ((r['decision_note'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Response: ${r['decision_note']}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

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
      return Column(
        children: [
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

class _AppealDecisionChip extends StatelessWidget {
  final String? status;
  const _AppealDecisionChip(this.status);

  @override
  Widget build(BuildContext context) => RoleChip(switch (status) {
    'pending' => 'Pending',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'closed' => 'Closed',
    _ => 'Unknown',
  }, error: status == 'rejected');
}

/// Approve (optional note) or reject (required note) one appeal.
class AppealDecisionDialog extends StatefulWidget {
  final String appealId;
  final bool approve;
  final String name;
  final String? email;
  const AppealDecisionDialog({
    super.key,
    required this.appealId,
    required this.approve,
    required this.name,
    this.email,
  });
  @override
  State<AppealDecisionDialog> createState() => _AppealDecisionDialogState();
}

class _AppealDecisionDialogState extends State<AppealDecisionDialog> {
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
    // _busy is set synchronously, so a second tap cannot send a second decision.
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.decideAppeal(
        appealId: widget.appealId,
        approve: widget.approve,
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
      if (_isStale(e, const [
        'appeal_already_decided',
        'appeal_not_current',
        'appeal_not_found',
      ])) {
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
    title: widget.approve ? 'Approve appeal' : 'Reject appeal',
    message: widget.approve
        ? 'Approving reactivates this account immediately. The appeal stays in the moderation history.'
        : "The account stays restricted and the member will see your explanation. Don't include health details or other sensitive personal information.",
    name: widget.name,
    email: widget.email,
    confirm: widget.approve ? 'Approve appeal' : 'Reject appeal',
    busyConfirm: widget.approve ? 'Approving...' : 'Rejecting...',
    busy: _busy,
    destructive: !widget.approve,
    form: _form,
    error: _error,
    onConfirm: _save,
    field: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(
          widget.approve ? 'Note (optional)' : 'Reason for rejection',
          requiredField: !widget.approve,
        ),
        _AdminTextField(
          controller: _note,
          maxLines: 4,
          maxLength: 1000,
          enabled: !_busy,
          validator: widget.approve
              ? validateApprovalNote
              : validateRejectionNote,
          decoration: InputDecoration(
            hintText: widget.approve
                ? 'Add a note for the moderation history'
                : 'Explain why the appeal is rejected',
          ),
        ),
      ],
    ),
  );
}
