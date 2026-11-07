part of 'admin.dart';

// Admin report management (20261106100000_admin_report_management.sql):
// list reports with status filters, review the stored evidence and a narrow
// conversation context, dismiss a report, or end the reported conversation.
// The server enforces every rule (admin-only, one decision per report, the
// conversation restriction); this UI only explains them. Member-written text
// is always shown as plain text.

enum _ReportFilter { open, dismissed, ended, all }

String _reportReasonLabel(String? reason) =>
    kReportReasons.where((r) => r.$1 == reason).firstOrNull?.$2 ?? 'Other';

String _memberName(Object? member) {
  if (member is! Map) return "Ma'ak member";
  if (member['account_exists'] == false) return 'Deleted account';
  final name = (member['name'] as String? ?? '').trim();
  return name.isEmpty ? "Ma'ak member" : name;
}

String _memberRole(Object? member) =>
    member is Map && member['account_exists'] != false
    ? _roleLabel(member['role'] as String?)
    : 'Account deleted';

String _messageTypeLabel(String? type) => switch (type) {
  'image' => 'Photo',
  'video' => 'Video',
  'voice' => 'Voice message',
  _ => 'Message',
};

String _deciderLabel(Map<String, dynamic> row) {
  final name = (row['decided_by_name'] as String? ?? '').trim();
  if (name.isEmpty) return 'an administrator';
  return row['decided_by_is_me'] == true ? '$name (you)' : name;
}

class _ReportStatusChip extends StatelessWidget {
  final String? status;
  const _ReportStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    // Dismissed = reviewed, no action needed: the same soft green as an
    // approved application, so it reads as resolved next to grey Open and
    // red Conversation ended.
    if (status == 'dismissed') {
      return Container(
        key: const ValueKey('report_status_dismissed'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Text(
          'Dismissed',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.success,
          ),
        ),
      );
    }
    return RoleChip(
      switch (status) {
        'open' => 'Open',
        'conversation_ended' => 'Conversation ended',
        'reviewed' => 'Reviewed',
        _ => 'Unknown',
      },
      error: status == 'conversation_ended',
      pending: status == 'open',
    );
  }
}

class ReportsAdminPage extends StatefulWidget {
  const ReportsAdminPage({super.key});
  @override
  State<ReportsAdminPage> createState() => _ReportsAdminPageState();
}

class _ReportsAdminPageState extends State<ReportsAdminPage> {
  // Rows stay visible while a refresh runs; only the first load shows a spinner.
  List<Map<String, dynamic>>? _rows;
  Object? _error;
  bool _loading = true;
  bool _installed = true;
  bool _opening = false;
  _ReportFilter _filter = _ReportFilter.open;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final rows = await SupabaseService.getReports().timeout(
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
      debugPrint('Reports load failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch();
  }

  Future<void> _open(Map<String, dynamic> report) async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReportDetailPage(report: report)),
      );
    } finally {
      _opening = false;
    }
    if (mounted) _reload();
  }

  static bool _inFilter(_ReportFilter filter, Map<String, dynamic> row) =>
      switch (filter) {
        _ReportFilter.open => row['status'] == 'open',
        _ReportFilter.dismissed => row['status'] == 'dismissed',
        _ReportFilter.ended => row['status'] == 'conversation_ended',
        _ReportFilter.all => true,
      };

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Message reports')),
    body: _AdminResponsiveBody(child: _body()),
  );

  Widget _filters(List<Map<String, dynamic>> all) {
    int count(_ReportFilter f) => all.where((r) => _inFilter(f, r)).length;
    return _FilterBar<_ReportFilter>(
      keyPrefix: 'report_filter',
      options: {
        _ReportFilter.all: 'All (${count(_ReportFilter.all)})',
        _ReportFilter.open: 'Open (${count(_ReportFilter.open)})',
        _ReportFilter.dismissed:
            'Dismissed (${count(_ReportFilter.dismissed)})',
        _ReportFilter.ended: 'Ended (${count(_ReportFilter.ended)})',
      },
      selected: _filter,
      onChanged: (value) => setState(() => _filter = value),
    );
  }

  Widget _body() {
    final all = _rows;
    if (all == null) {
      if (_error != null) {
        return EmptyState(
          'Could not load reports',
          friendlyError(_error!),
          retry: _reload,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final rows = all.where((r) => _inFilter(_filter, r)).toList();
    final open = all.where((r) => r['status'] == 'open').length;
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              if (_installed) ...[
                Text(
                  open == 1
                      ? '1 report needs review'
                      : '$open reports need review',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                _filters(all),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _RefreshFailedNotice(error: _error!, retry: _reload),
              ],
              const SizedBox(height: 16),
              if (!_installed)
                const EmptyState(
                  'Reports are not available yet',
                  'The report management database update has not been installed.',
                  icon: Icons.flag_outlined,
                )
              else if (all.isEmpty)
                const EmptyState(
                  'No reports yet',
                  'Messages reported by members will appear here.',
                  icon: Icons.flag_outlined,
                )
              else if (rows.isEmpty)
                EmptyState(
                  switch (_filter) {
                    _ReportFilter.open => 'No open reports',
                    _ReportFilter.dismissed => 'No dismissed reports',
                    _ReportFilter.ended => 'No ended conversations',
                    _ReportFilter.all => 'No reports',
                  },
                  _filter == _ReportFilter.open
                      ? 'Nothing needs review right now.'
                      : 'Try another filter.',
                  icon: Icons.flag_outlined,
                ),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final row in rows)
                    SizedBox(
                      width: cardWidth,
                      child: _ReportCard(report: row, onTap: () => _open(row)),
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

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onTap;
  const _ReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final others = (report['conversation_open_reports'] as num? ?? 0).toInt();
    final preview = report['message_type'] == 'text'
        ? '"${report['message_preview'] ?? ''}"'
        : _messageTypeLabel(report['message_type'] as String?);
    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.selectedCardFill,
            child: Icon(Icons.flag_outlined, color: AppColors.primaryNavy),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _reportReasonLabel(report['reason'] as String?),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reported member: ${_memberName(report['reported'])} · ${_memberRole(report['reported'])}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Reported by ${_memberName(report['reporter'])} on ${formatDay(report['created_at'] as String?)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ReportStatusChip(report['status'] as String?),
                    if (report['reported'] is Map &&
                        (report['reported'] as Map)['is_blocked'] == true)
                      const RoleChip('Account blocked', error: true),
                    if (report['status'] == 'open' && others > 1)
                      RoleChip('$others open reports in this conversation'),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class ReportDetailPage extends StatefulWidget {
  /// A row from admin_list_reports().
  final Map<String, dynamic> report;
  const ReportDetailPage({super.key, required this.report});
  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  Map<String, dynamic>? _details;
  // Restriction and lift events for this report's conversation; null when the
  // lift migration is not installed or the history could not be loaded.
  List<Map<String, dynamic>>? _restrictionHistory;
  // admin_report_media: the reported item and open-report context media. Null
  // when not loaded, the migration is missing, or loading failed.
  Map<String, dynamic>? _media;
  bool _mediaLoaded = false;
  Object? _error;
  bool _loading = true;
  bool _acting = false;
  String? _notice;

  String get _reportId => widget.report['report_id'] as String? ?? '';
  Map<String, dynamic> get _r => _details ?? widget.report;
  bool get _open => _r['status'] == 'open';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final details = await SupabaseService.getReportDetails(
        _reportId,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        // Another admin may have decided since the list loaded.
        if (_details == null &&
            widget.report['status'] == 'open' &&
            details['status'] != 'open') {
          _notice =
              'Another administrator has already decided this report. Its latest status is shown.';
        }
        _details = details;
        _error = null;
      });
      // Secondary: a failure here never hides the report itself.
      final requestId = details['request_id'] as String?;
      if (requestId != null) {
        try {
          final history = await SupabaseService.getRestrictionHistory(
            requestId,
          ).timeout(const Duration(seconds: 15));
          if (mounted) setState(() => _restrictionHistory = history);
        } catch (error) {
          debugPrint('Restriction history load failed: ${error.runtimeType}');
        }
      }
      if (_hasMedia(details)) {
        try {
          final media = await SupabaseService.getReportMedia(
            _reportId,
          ).timeout(const Duration(seconds: 15));
          if (mounted) setState(() => _media = media);
        } catch (error) {
          debugPrint('Report media load failed: ${error.runtimeType}');
        } finally {
          if (mounted) setState(() => _mediaLoaded = true);
        }
      }
    } catch (error) {
      debugPrint('Report details load failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _fetch();
  }

  Future<void> _liftRestriction(Map conversation) async {
    final requestId = _r['request_id'] as String?;
    if (_acting || requestId == null) return;
    setState(() => _acting = true);
    try {
      final outcome = await showDialog<ModerationOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LiftRestrictionDialog(
          requestId: requestId,
          participants:
              '${_memberName(conversation['help_seeker'])} & ${_memberName(conversation['volunteer'])}',
        ),
      );
      if (!mounted || outcome == null) return;
      if (outcome.stale) {
        _notice =
            'This restriction changed elsewhere. The latest status is shown.';
      } else {
        _notice = null;
        showSuccess(
          context,
          'Restriction lifted. Both participants were notified.',
        );
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _decide({required bool endConversation}) async {
    if (_acting || !_open) return;
    setState(() => _acting = true);
    try {
      final outcome = await showDialog<ModerationOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReportDecisionDialog(
          reportId: _reportId,
          endConversation: endConversation,
          reportedName: _memberName(_r['reported']),
          openReports: (_r['conversation_open_reports'] as num? ?? 1).toInt(),
        ),
      );
      if (!mounted || outcome == null) return;
      if (outcome.stale) {
        _notice =
            'This report or its conversation changed elsewhere. The latest status is shown.';
      } else {
        _notice = null;
        showSuccess(
          context,
          endConversation
              ? (outcome.text ?? 'Conversation ended.')
              : 'Report dismissed. The conversation is not affected.',
        );
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Report details')),
    body: _AdminResponsiveBody(child: _body()),
  );

  Widget _body() {
    final d = _details;
    if (d == null) {
      if (_error != null) {
        return EmptyState(
          'Could not load this report',
          friendlyError(_error!),
          retry: _refresh,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final conversation = d['conversation'] as Map? ?? const {};
    final available = conversation['exists'] == true;
    final restricted = conversation['restricted_at'] != null;
    final canEnd =
        available && !restricted && conversation['status'] == 'accepted';
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        final report = _reportCard(d);
        final people = _peopleCard(d);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                _reportReasonLabel(d['reason'] as String?),
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ReportStatusChip(d['status'] as String?),
                  RoleChip('Reported ${formatDay(d['created_at'] as String?)}'),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _RefreshFailedNotice(error: _error!, retry: _refresh),
              ],
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _section('Report', report)),
                    const SizedBox(width: 16),
                    Expanded(child: _section('People', people)),
                  ],
                )
              else ...[
                _section('Report', report),
                _section('People', people),
              ],
              _section('Reported message', _evidenceCard(d)),
              _section('Conversation context', _contextSection(d)),
              _section('Conversation status', _conversationCard(conversation)),
              if ((_restrictionHistory ?? const []).isNotEmpty)
                _section(
                  'Restriction history',
                  _restrictionHistorySection(_restrictionHistory!),
                ),
              if ((d['other_reports'] as List? ?? const []).isNotEmpty)
                _section(
                  'Other reports in this conversation',
                  _otherReports(d['other_reports'] as List),
                ),
              _section('Moderation history', _history(d)),
              const SizedBox(height: 28),
              if (_notice != null) ...[
                _InfoNotice(_notice!),
                const SizedBox(height: 14),
              ],
              if (_open) ...[
                if (!canEnd) ...[
                  _InfoNotice(
                    restricted
                        ? 'An administrator has already ended this conversation. You can dismiss this report.'
                        : 'This conversation is no longer available, so it cannot be ended. You can dismiss this report.',
                  ),
                  const SizedBox(height: 14),
                ],
                _actions(canEnd, sideBySide: constraints.maxWidth >= 480),
              ],
            ],
          ),
        );
      },
    );
  }

  // Side by side on wider screens; stacked full width on phones so neither
  // label wraps. The destructive action is always last.
  Widget _actions(bool canEnd, {required bool sideBySide}) {
    final dismiss = OutlinedButton(
      onPressed: _acting || _loading
          ? null
          : () => _decide(endConversation: false),
      child: const Text('Dismiss report'),
    );
    final end = FilledButton(
      onPressed: _acting || _loading || !canEnd
          ? null
          : () => _decide(endConversation: true),
      style: FilledButton.styleFrom(backgroundColor: AppColors.error),
      child: const Text('End conversation'),
    );
    if (sideBySide) {
      return Row(
        children: [
          Expanded(child: dismiss),
          const SizedBox(width: 12),
          Expanded(child: end),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [dismiss, const SizedBox(height: 12), end],
    );
  }

  Widget _section(String title, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [SectionTitle(title), child],
  );

  Widget _reportCard(Map<String, dynamic> d) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow('Reason', _reportReasonLabel(d['reason'] as String?)),
        _InfoRow(
          'Description from the reporter',
          (d['description'] as String? ?? '').trim().isEmpty
              ? 'No description was added.'
              : d['description'] as String,
        ),
        _InfoRow('Reported on', formatDay(d['created_at'] as String?)),
      ],
    ),
  );

  Widget _peopleCard(Map<String, dynamic> d) {
    Widget person(String label, Object? member) {
      final blocked = member is Map && member['is_blocked'] == true;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.selectedCardFill,
              child: Text(initials(_memberName(member))),
            ),
            const SizedBox(width: 12),
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
                  Text(
                    _memberName(member),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _memberRole(member),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (blocked) const RoleChip('Blocked', error: true),
          ],
        ),
      );
    }

    return SurfaceCard(
      child: Column(
        children: [
          person('Reported member', d['reported']),
          const Divider(),
          person('Reported by', d['reporter']),
        ],
      ),
    );
  }

  Widget _evidenceCard(Map<String, dynamic> d) {
    final now = d['message_now'] as Map? ?? const {};
    final type = d['message_type'] as String?;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sent ${formatDay(d['message_sent_at'] as String?)} by ${_memberName(d['reported'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          if (type != 'text') _reportedMedia(d, type),
          if (type == 'text')
            Text(
              d['message_body'] as String? ?? '',
              key: const ValueKey('report_evidence'),
              style: const TextStyle(height: 1.5),
            ),
          const SizedBox(height: 10),
          Text(
            now['exists'] != true
                ? 'The original message is no longer available. This is the copy saved when it was reported.'
                : now['deleted'] == true
                ? 'The sender deleted this message after it was reported. This is the copy saved with the report.'
                : 'Saved when the message was reported.',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  static const _defaultMediaBodies = {'Photo', 'Video', 'Voice message'};

  static bool _hasMedia(Map<String, dynamic> d) =>
      (d['message_type'] ?? 'text') != 'text' ||
      (d['context'] as List? ?? const []).any(
        (m) => m is Map && m['message_type'] != 'text' && m['deleted'] != true,
      );

  // A caption typed with the media; the default "Photo"/"Video" body is not one.
  Widget? _caption(String? body) {
    final text = (body ?? '').trim();
    if (text.isEmpty || _defaultMediaBodies.contains(text)) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        key: const ValueKey('report_media_caption'),
        style: const TextStyle(height: 1.4),
      ),
    );
  }

  Widget _mediaPlaceholder(String text) => Text(
    text,
    style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4),
  );

  Widget _reportedMedia(Map<String, dynamic> d, String? type) {
    final item = _media?['reported'];
    final caption = _caption(d['message_body'] as String?);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item is Map)
          AdminReportMediaView(
            key: const ValueKey('report_media_reported'),
            item: Map<String, dynamic>.from(item),
          )
        else if (!_mediaLoaded)
          const LinearProgressIndicator()
        else
          _mediaPlaceholder(
            '${_messageTypeLabel(type)} (could not be loaded. Refresh to try again.)',
          ),
        ?caption,
      ],
    );
  }

  Widget _contextMessage(Map m) {
    final type = m['message_type'] as String?;
    if (type == 'text' || m['deleted'] == true) {
      return Text(
        m['body'] as String? ?? '',
        style: TextStyle(
          height: 1.4,
          fontStyle: m['deleted'] == true ? FontStyle.italic : FontStyle.normal,
        ),
      );
    }
    final label = _messageTypeLabel(type);
    if (m['is_reported'] == true) {
      return _mediaPlaceholder('$label (shown above in the reported message)');
    }
    final item = (_media?['context'] as List? ?? const [])
        .whereType<Map>()
        .where((c) => c['message_id'] == m['message_id'])
        .firstOrNull;
    if (item != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminReportMediaView(
            key: ValueKey('report_media_context_${m['message_id']}'),
            item: Map<String, dynamic>.from(item),
          ),
          ?_caption(m['body'] as String?),
        ],
      );
    }
    if (_media != null && _media!['context_media_allowed'] != true) {
      return _mediaPlaceholder(
        '$label (context media is shown only while the report is open)',
      );
    }
    return _mediaPlaceholder(
      _mediaLoaded ? '$label (not available)' : '$label (loading…)',
    );
  }

  Widget _contextSection(Map<String, dynamic> d) {
    final messages = (d['context'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    if (messages.isEmpty) {
      return const SurfaceCard(
        child: Text(
          'The conversation is no longer available, for example because an account was deleted.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final reportedName = _memberName(d['reported']);
    final reporterName = _memberName(d['reporter']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Up to 5 messages before and after the reported message.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        for (final m in messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: m['is_reported'] == true
                    ? AppColors.selectedCardFill
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: m['is_reported'] == true
                      ? AppColors.error
                      : AppColors.divider,
                  width: m['is_reported'] == true ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        m['sender'] == 'reported'
                            ? reportedName
                            : m['sender'] == 'reporter'
                            ? reporterName
                            : "Ma'ak member",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        formatDay(m['created_at'] as String?),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (m['is_reported'] == true)
                        const RoleChip('Reported message', error: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _contextMessage(m),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _conversationCard(Map conversation) {
    if (conversation['exists'] != true) {
      return const SurfaceCard(
        child: Text(
          'This conversation no longer exists.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final restrictedBy = (conversation['restricted_by_name'] as String? ?? '')
        .trim();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(
            'Status',
            conversation['restricted_at'] != null
                ? 'Ended by an administrator'
                : conversation['ended_at'] != null
                ? 'Ended by a participant'
                : 'Active',
          ),
          _InfoRow('Help seeker', _memberName(conversation['help_seeker'])),
          _InfoRow('Volunteer', _memberName(conversation['volunteer'])),
          if (conversation['restricted_at'] != null) ...[
            _InfoRow(
              'Ended on',
              formatDay(conversation['restricted_at'] as String?),
            ),
            _InfoRow(
              'Ended by',
              conversation['restricted_by_is_me'] == true &&
                      restrictedBy.isNotEmpty
                  ? '$restrictedBy (you)'
                  : restrictedBy,
            ),
            _InfoRow(
              'Reason shown to participants',
              conversation['restriction_reason'] as String?,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('lift_restriction_button'),
              onPressed: _acting || _loading
                  ? null
                  : () => _liftRestriction(conversation),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Lift restriction'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _restrictionHistorySection(List<Map<String, dynamic>> events) =>
      Column(
        children: [
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ReportHistoryEntry(
                icon: e['action'] == 'lifted'
                    ? Icons.lock_open_outlined
                    : Icons.lock_outline,
                color: e['action'] == 'lifted'
                    ? AppColors.success
                    : AppColors.error,
                title: () {
                  final name = (e['actor_name'] as String? ?? '').trim();
                  final who = e['actor_is_me'] == true && name.isNotEmpty
                      ? '$name (you)'
                      : name;
                  return e['action'] == 'lifted'
                      ? 'Restriction lifted by $who'
                      : 'Conversation restricted by $who';
                }(),
                date: e['created_at'] as String?,
                note: e['reason'] as String?,
              ),
            ),
        ],
      );

  Widget _otherReports(List others) => Column(
    children: [
      for (final o in others.whereType<Map>())
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SurfaceCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _reportReasonLabel(o['reason'] as String?),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          'By ${(o['reporter_name'] as String?) ?? 'Deleted account'}',
                          formatDay(o['created_at'] as String?),
                          if (o['same_message'] == true) 'same message',
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _ReportStatusChip(o['status'] as String?),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _history(Map<String, dynamic> d) {
    final status = d['status'] as String?;
    final decided = d['decided_at'] != null;
    return Column(
      children: [
        _ReportHistoryEntry(
          icon: Icons.flag_outlined,
          color: AppColors.primaryNavy,
          title: 'Reported by ${_memberName(d['reporter'])}',
          date: d['created_at'] as String?,
        ),
        if (decided) ...[
          const SizedBox(height: 12),
          _ReportHistoryEntry(
            icon: status == 'conversation_ended'
                ? Icons.lock_outline
                : Icons.check_circle_outline,
            color: status == 'conversation_ended'
                ? AppColors.error
                : AppColors.success,
            title: status == 'conversation_ended'
                ? 'Conversation ended by ${_deciderLabel(d)}'
                : 'Dismissed by ${_deciderLabel(d)}',
            date: d['decided_at'] as String?,
            note: d['decision_note'] as String?,
          ),
        ] else ...[
          const SizedBox(height: 12),
          const _ReportHistoryEntry(
            icon: Icons.hourglass_empty,
            color: AppColors.textMuted,
            title: 'Waiting for an administrator decision',
          ),
        ],
      ],
    );
  }
}

class _ReportHistoryEntry extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? date, note;
  const _ReportHistoryEntry({
    required this.icon,
    required this.color,
    required this.title,
    this.date,
    this.note,
  });

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (date != null) ...[
                const SizedBox(height: 4),
                Text(
                  formatDay(date),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              if ((note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(note!, style: const TextStyle(height: 1.5)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Confirms dismissing a report, or ending its conversation, with a required
/// reason (1-500 characters) recorded in the moderation history.
class ReportDecisionDialog extends StatefulWidget {
  final String reportId;
  final bool endConversation;
  final String reportedName;
  final int openReports;
  const ReportDecisionDialog({
    super.key,
    required this.reportId,
    required this.endConversation,
    required this.reportedName,
    this.openReports = 1,
  });
  @override
  State<ReportDecisionDialog> createState() => _ReportDecisionDialogState();
}

class _ReportDecisionDialogState extends State<ReportDecisionDialog> {
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
    // _busy is set synchronously, so a second tap cannot send a second decision.
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? text;
      if (widget.endConversation) {
        final result = await SupabaseService.endReportedConversation(
          reportId: widget.reportId,
          reason: _reason.text,
        );
        final resolved = (result['resolved_reports'] as num? ?? 1).toInt();
        text = resolved > 1
            ? 'Conversation ended. $resolved open reports were resolved.'
            : 'Conversation ended.';
      } else {
        await SupabaseService.dismissReport(
          reportId: widget.reportId,
          reason: _reason.text,
        );
      }
      if (mounted) {
        Navigator.pop<ModerationOutcome>(context, (stale: false, text: text));
      }
    } catch (e) {
      if (!mounted) return;
      if (_isStale(e, const [
        'report_already_decided',
        'report_not_found',
        'conversation_already_restricted',
        'conversation_unavailable',
        'conversation_changed',
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
  Widget build(BuildContext context) {
    final end = widget.endConversation;
    final others = widget.openReports > 1
        ? ' Resolves all ${widget.openReports} open reports here.'
        : '';
    return _ModerationDialog(
      title: end ? 'End this conversation?' : 'Dismiss this report?',
      message: end
          ? 'Both participants can no longer chat or reopen it. Messages are kept; no account is blocked.$others'
          : 'No action is taken and the conversation stays open. Only admins see your reason.',
      name: widget.reportedName,
      email: end ? 'Conversation with the reported member' : 'Reported member',
      confirm: end ? 'End conversation' : 'Dismiss report',
      busyConfirm: end ? 'Ending...' : 'Dismissing...',
      busy: _busy,
      destructive: end,
      form: _form,
      error: _error,
      onConfirm: _save,
      field: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(
            end ? 'Reason shown to both participants' : 'Reason for dismissing',
            requiredField: true,
          ),
          _AdminTextField(
            controller: _reason,
            maxLines: 4,
            maxLength: 500,
            enabled: !_busy,
            validator: end
                ? validateEndConversationReason
                : validateDismissReason,
            decoration: InputDecoration(
              hintText: end
                  ? 'For example: Repeated harassment in this conversation'
                  : 'For example: No rule was broken',
              // Both participants see this reason in their notification.
              helperText: end
                  ? "Don't name the reporter or include health details."
                  : null,
              helperMaxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirms lifting an administrator restriction, with a required reason that
/// only administrators see (participants get a generic notice).
class LiftRestrictionDialog extends StatefulWidget {
  final String requestId;
  final String participants;
  const LiftRestrictionDialog({
    super.key,
    required this.requestId,
    required this.participants,
  });
  @override
  State<LiftRestrictionDialog> createState() => _LiftRestrictionDialogState();
}

class _LiftRestrictionDialogState extends State<LiftRestrictionDialog> {
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
    // _busy is set synchronously, so a second tap cannot send a second lift.
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.liftConversationRestriction(
        requestId: widget.requestId,
        reason: _reason.text,
      );
      if (mounted) {
        Navigator.pop<ModerationOutcome>(context, (stale: false, text: null));
      }
    } catch (e) {
      if (!mounted) return;
      if (_isStale(e, const [
        'conversation_not_restricted',
        'conversation_unavailable',
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
    title: 'Lift this restriction?',
    message:
        'They can chat again unless a participant ended the chat or an account is blocked. Both get a notice without your reason.',
    name: widget.participants,
    email: 'Conversation participants',
    confirm: 'Lift restriction',
    busyConfirm: 'Lifting...',
    busy: _busy,
    destructive: false,
    form: _form,
    error: _error,
    onConfirm: _save,
    field: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Reason (admins only)', requiredField: true),
        _AdminTextField(
          controller: _reason,
          maxLines: 4,
          maxLength: 500,
          enabled: !_busy,
          validator: validateLiftReason,
          decoration: const InputDecoration(
            hintText: 'For example: Restricted by mistake',
          ),
        ),
      ],
    ),
  );
}
