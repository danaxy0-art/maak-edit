import 'dart:async';
import '../../backend/models/message_order.dart';
import 'matching_page.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/services/supabase_service.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'feedback.dart';
import 'chat_media.dart';

class DataListPage extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback) item;
  final String emptyTitle, emptyText;
  final Widget? header;
  final Widget Function(VoidCallback)? headerBuilder;
  const DataListPage({
    super.key,
    required this.title,
    required this.load,
    required this.item,
    this.emptyTitle = 'Nothing here yet',
    this.emptyText = 'Your activity will appear here.',
    this.header,
    this.headerBuilder,
  });
  @override
  State<DataListPage> createState() => _DataListPageState();
}

class _DataListPageState extends State<DataListPage> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = widget.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ResponsiveBody(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, s) {
          if (s.hasError) {
            return EmptyState(
              'Could not load data',
              friendlyError(s.error!),
              retry: _reload,
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.header != null) widget.header!,
                if (widget.headerBuilder != null)
                  widget.headerBuilder!(_reload),
                if (s.data!.isEmpty)
                  EmptyState(widget.emptyTitle, widget.emptyText),
                for (final row in s.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: widget.item(context, row, _reload),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class VolunteerDirectoryPage extends StatefulWidget {
  const VolunteerDirectoryPage({super.key});
  @override
  State<VolunteerDirectoryPage> createState() => _VolunteerDirectoryPageState();
}

class _VolunteerDirectoryPageState extends State<VolunteerDirectoryPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String _search = '';
  @override
  void initState() {
    super.initState();
    _future = SupabaseService.getVolunteers();
  }

  // Block body: an arrow would hand the new Future to setState.
  void _retry() => setState(() {
    _future = SupabaseService.getVolunteers();
  });

  void _openMatches() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const MatchingPage()),
  );

  @override
  Widget build(BuildContext context) => MaakPage(
    title: 'Find a volunteer',
    children: (context, wide) => [
      _searchAndMatches(wide),
      const SizedBox(height: MaakSpace.xl),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, s) {
          if (s.hasError) {
            return StateMessage(
              title: 'Could not load volunteers',
              message: friendlyError(s.error!),
              icon: Icons.cloud_off_outlined,
              retry: _retry,
            );
          }
          if (!s.hasData) {
            return const ListSkeleton(label: 'Loading volunteers');
          }
          final rows = s.data!
              .where(
                (r) => '${r['full_name']} ${r['condition']} ${r['language']}'
                    .toLowerCase()
                    .contains(_search),
              )
              .toList();
          if (rows.isEmpty) {
            return const StateMessage(
              title: 'No volunteers found',
              message: 'Try another search or check again later.',
              icon: Icons.person_search_outlined,
            );
          }
          final cards = [
            for (final row in rows)
              _VolunteerCard(
                volunteer: row,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VolunteerDetailPage(volunteer: row),
                  ),
                ),
              ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  rows.length == 1
                      ? '1 volunteer'
                      : '${rows.length} volunteers',
                  style: MaakText.caption,
                ),
              ),
              const SizedBox(height: MaakSpace.md),
              if (wide)
                PairedGrid(children: cards)
              else
                for (final (i, card) in cards.indexed) ...[
                  if (i > 0) const SizedBox(height: MaakSpace.md),
                  card,
                ],
            ],
          );
        },
      ),
    ],
  );

  Widget _searchAndMatches(bool wide) {
    final search = MaakSearchField(
      hint: 'Search name, condition or language',
      maxLength: 100,
      onChanged: (v) => setState(() => _search = v.toLowerCase()),
    );
    final matches = _RecommendedMatchesCard(onTap: _openMatches);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          matches,
          const SizedBox(height: MaakSpace.md),
          search,
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 13, child: search),
        const SizedBox(width: MaakSpace.md),
        Expanded(flex: 10, child: matches),
      ],
    );
  }
}

/// Labelled entry to the recommended matches, replacing the old icon action.
class _RecommendedMatchesCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RecommendedMatchesCard({required this.onTap});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: MaakGradients.orb,
      borderRadius: BorderRadius.circular(MaakRadius.card),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(MaakRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            MaakSpace.md,
            MaakSpace.md,
            MaakSpace.sm,
            MaakSpace.md,
          ),
          child: Row(
            children: [
              const IconBadge(Icons.auto_awesome, color: Color(0xC0FFFFFF)),
              const SizedBox(width: MaakSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommended matches',
                      style: MaakText.itemTitle,
                    ),
                    Text(
                      'Volunteers who share your conditions',
                      style: MaakText.body.copyWith(
                        color: MaakColors.onHero,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: MaakColors.onHero),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VolunteerCard extends StatelessWidget {
  final Map<String, dynamic> volunteer;
  final VoidCallback onTap;
  const _VolunteerCard({required this.volunteer, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final name = volunteer['full_name'] as String? ?? 'Volunteer';
    final description = (volunteer['description'] as String? ?? '').trim();
    final language = volunteer['language'] as String?;
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.fromSTEB(
        MaakSpace.lg,
        MaakSpace.lg,
        MaakSpace.sm,
        MaakSpace.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(initials(volunteer['full_name'] as String? ?? 'V')),
          const SizedBox(width: MaakSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: MaakText.itemTitle),
                const SizedBox(height: MaakSpace.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in conditionNames(volunteer['condition']))
                      ConditionChip(c),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: MaakSpace.sm),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MaakText.body.copyWith(fontSize: 13),
                  ),
                ],
                if (language != null && language.isNotEmpty) ...[
                  const SizedBox(height: MaakSpace.sm),
                  MetaLine(icon: Icons.language, text: language),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsetsDirectional.only(top: MaakSpace.md),
            child: Icon(Icons.chevron_right, color: MaakColors.muted),
          ),
        ],
      ),
    );
  }
}

class VolunteerDetailPage extends StatefulWidget {
  final Map<String, dynamic> volunteer;
  const VolunteerDetailPage({super.key, required this.volunteer});
  @override
  State<VolunteerDetailPage> createState() => _VolunteerDetailPageState();
}

class _VolunteerDetailPageState extends State<VolunteerDetailPage> {
  bool _busy = false, _sent = false;
  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      await SupabaseService.requestSupport(
        widget.volunteer['user_id'] as String,
      );
      if (mounted) {
        setState(() => _sent = true);
        showSuccess(context, 'Support request sent.');
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // Present when opened from Matching: conditions shared with this member.
  Set<String> get _shared => {
    for (final c in widget.volunteer['shared_conditions'] as List? ?? [])
      if (c is Map) '${c['name']}',
  };

  Widget _button() => PillButton(
    _sent ? 'Request sent' : 'Request support',
    icon: _sent ? Icons.check : null,
    busy: _busy,
    expand: true,
    onPressed: _sent ? null : _request,
  );

  @override
  Widget build(BuildContext context) {
    final description = (widget.volunteer['description'] as String? ?? '')
        .trim();
    final details = [
      if (description.isNotEmpty) ...[
        _ProfileSection(
          title: 'Lived experience',
          child: Text(
            description,
            style: MaakText.body.copyWith(
              color: MaakColors.onHero,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: MaakSpace.md),
      ],
      _ProfileSection(
        title: 'Support preferences',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PreferenceRow(
              icon: Icons.favorite_border,
              label: 'Conditions',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in conditionNames(widget.volunteer['condition']))
                    ConditionChip(c, shared: _shared.contains(c)),
                ],
              ),
            ),
            const SizedBox(height: MaakSpace.md),
            _PreferenceRow(
              icon: Icons.language,
              label: 'Language',
              child: Text(
                '${widget.volunteer['language'] ?? ''}',
                style: MaakText.body.copyWith(color: MaakColors.ink),
              ),
            ),
          ],
        ),
      ),
    ];
    return MaakPage(
      title: 'Volunteer profile',
      bottomBar: (wide) => wide ? null : StickyActionBar(child: _button()),
      children: (context, wide) => wide
          ? [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _identity(),
                        const SizedBox(height: MaakSpace.lg),
                        _button(),
                      ],
                    ),
                  ),
                  const SizedBox(width: MaakSpace.xxl),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: details,
                    ),
                  ),
                ],
              ),
            ]
          : [_identity(), const SizedBox(height: MaakSpace.lg), ...details],
    );
  }

  Widget _identity() => Container(
    padding: const EdgeInsets.fromLTRB(
      MaakSpace.xl,
      MaakSpace.xxl,
      MaakSpace.xl,
      MaakSpace.xl,
    ),
    decoration: BoxDecoration(
      gradient: MaakGradients.orb,
      borderRadius: BorderRadius.circular(MaakRadius.hero),
    ),
    child: Column(
      children: [
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: MaakColors.surface,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials(widget.volunteer['full_name'] as String? ?? ''),
            style: MaakText.cardTitle.copyWith(fontSize: 28),
          ),
        ),
        const SizedBox(height: MaakSpace.md),
        Text(
          widget.volunteer['full_name'] as String? ?? 'Volunteer',
          textAlign: TextAlign.center,
          style: MaakText.greeting.copyWith(fontSize: 28),
        ),
        const SizedBox(height: MaakSpace.md),
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 12, 6),
          decoration: BoxDecoration(
            color: const Color(0xCCFFFFFF),
            borderRadius: BorderRadius.circular(MaakRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: MaakColors.ink,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Approved volunteer',
                  style: MaakText.caption.copyWith(
                    color: MaakColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _ProfileSection({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(MaakSpace.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: MaakText.section.copyWith(fontSize: 16)),
        ),
        const SizedBox(height: MaakSpace.md),
        child,
      ],
    ),
  );
}

class _PreferenceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _PreferenceRow({
    required this.icon,
    required this.label,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconBadge(icon, size: 36),
      const SizedBox(width: MaakSpace.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: MaakText.caption),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    ],
  );
}

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Support requests',
    load: SupabaseService.getRequests,
    emptyTitle: 'No requests yet',
    emptyText: 'New help seeker requests will appear here.',
    item: (context, row, refresh) => SurfaceCard(
      padding: const EdgeInsets.all(MaakSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(
                initials(row['contact_name'] as String? ?? 'Help seeker'),
              ),
              const SizedBox(width: MaakSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['contact_name'] as String? ?? 'Help seeker',
                      style: MaakText.itemTitle,
                    ),
                    if ((row['condition'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        row['condition'] as String,
                        style: MaakText.body.copyWith(fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // The status text is shown as stored; the icon keeps it
                    // from relying on colour alone.
                    StatusPill(
                      label: row['status'] as String,
                      icon: switch (row['status']) {
                        'pending' => Icons.schedule,
                        'accepted' => Icons.check,
                        'canceled' => Icons.block,
                        _ => Icons.close,
                      },
                      color: switch (row['status']) {
                        'pending' => MaakColors.blush,
                        'accepted' => MaakColors.selected,
                        _ => MaakColors.fill,
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((row['description'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: MaakSpace.md),
              child: Text(
                row['description'] as String,
                style: MaakText.body.copyWith(color: MaakColors.ink),
              ),
            ),
          if (row['status'] == 'pending')
            RequestDecisionButtons(
              key: ValueKey(row['id']),
              requestId: row['id'] as String,
              onSaved: refresh,
            ),
          if (row['status'] == 'accepted') ...[
            const SizedBox(height: 12),
            PrimaryButton(
              'Open conversation',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConversationPage(
                    requestId: row['id'] as String,
                    name: row['contact_name'] as String? ?? 'Your peer',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class RequestDecisionButtons extends StatefulWidget {
  final String requestId;
  final VoidCallback onSaved;
  const RequestDecisionButtons({
    super.key,
    required this.requestId,
    required this.onSaved,
  });
  @override
  State<RequestDecisionButtons> createState() => _RequestDecisionButtonsState();
}

class _RequestDecisionButtonsState extends State<RequestDecisionButtons> {
  bool _busy = false, _saved = false;
  Future<void> _decide(bool accept) async {
    if (_busy || _saved) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.decideRequest(widget.requestId, accept);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showAppError(context, e);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _saved = true;
      _busy = false;
    });
    showSuccess(
      context,
      accept ? 'Support request accepted.' : 'Support request declined.',
    );
    // The decision has committed. A refresh failure must not offer to repeat it.
    try {
      widget.onSaved();
    } catch (_) {
      if (mounted) {
        showSuccess(
          context,
          'Decision saved. Reopen this page to refresh the list.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy || _saved ? null : () => _decide(false),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PrimaryButton(
            'Accept',
            busy: _busy,
            onPressed: _busy || _saved ? null : () => _decide(true),
          ),
        ),
      ],
    ),
  );
}

class ConversationsPage extends StatelessWidget {
  const ConversationsPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Messages',
    load: () async => (await SupabaseService.getRequests())
        .where((r) => r['status'] == 'accepted')
        .toList(),
    emptyTitle: 'Start a connection',
    emptyText: 'Accepted support requests become conversations here.',
    item: (context, row, reload) => SurfaceCard(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConversationPage(
              requestId: row['id'] as String,
              name: row['contact_name'] as String? ?? 'Your peer',
            ),
          ),
        );
        reload();
      },
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.selectedCardFill,
            child: Text(initials(row['contact_name'] as String? ?? 'Peer')),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['contact_name'] as String? ?? 'Your peer',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                Text(
                  row['last_message'] as String? ?? 'Say hello to your peer.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted),
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

class ConversationPage extends StatefulWidget {
  final String requestId, name;
  const ConversationPage({
    super.key,
    required this.requestId,
    required this.name,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage>
    with WidgetsBindingObserver {
  static const Color _sendColor = Color(0xFFD97883);
  static const Color _dangerColor = Color(0xFFB54747);
  static const Color _dangerTint = Color(0xFFFCE8E6);
  static const Color _endedTint = Color(0xFFF6EDF0);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  late Stream<List<Map<String, dynamic>>> _stream;
  String? _lastMessageId;
  String? _sendError;
  bool _mediaBusy = false;
  bool _reading = false;
  bool _busy = false;
  bool _ending = false;
  bool _reopenBusy = false;
  late Future<List<Map<String, dynamic>>> _reopenFuture;
  Timer? _reopenRefreshTimer;
  List<Map<String, dynamic>> _lastReopenRequests = [];

  Future<List<Map<String, dynamic>>> _fetchReopenRequests() async {
    final rows = await SupabaseService.client
        .from('chat_reopen_requests')
        .select('id,request_id,requested_by,recipient_id,status,created_at')
        .eq('request_id', widget.requestId)
        .order('created_at', ascending: true);
    _lastReopenRequests = List<Map<String, dynamic>>.from(rows);
    return _lastReopenRequests;
  }

  void _refreshReopenRequests() {
    if (!mounted) return;
    setState(() => _reopenFuture = _fetchReopenRequests());
  }

  bool _ended = false;
  String? _endedBy;
  DateTime? _currentEndedAt;

  bool _statusLoading = true;
  String? _statusError;
  late Stream<List<Map<String, dynamic>>> _reactionsStream;
  StreamSubscription<List<Map<String, dynamic>>>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = SupabaseService.messageStream(widget.requestId);
    _reactionsStream = SupabaseService.chatReactionsStream(widget.requestId);
    _reopenFuture = _fetchReopenRequests();
    _reopenRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _ended && !_reopenBusy) {
        _refreshReopenRequests();
      }
    });
    _loadStatus();
    _statusSubscription = SupabaseService.chatStatusStream(widget.requestId)
        .listen(
          (rows) {
            if (mounted && rows.isNotEmpty) {
              setState(() {
                _ended = rows.first['ended_at'] != null;
                if (_ended) _mediaBusy = false;
                _endedBy = rows.first['ended_by'] as String?;
                _currentEndedAt = DateTime.tryParse(
                  '${rows.first['ended_at'] ?? ''}',
                );
                _statusLoading = false;
                _statusError = null;
              });
            }
          },
          onError: (Object _) {
            if (mounted) _loadStatus();
          },
        );
    _input.addListener(_refreshInput);
  }

  void _refreshInput() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _reopenRefreshTimer?.cancel();
    _statusSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _input.removeListener(_refreshInput);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadStatus();
      setState(() {});
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await SupabaseService.client
          .from('support_requests')
          .select('ended_at, ended_by')
          .eq('id', widget.requestId)
          .single();
      final ended = status['ended_at'] != null;
      if (mounted) {
        setState(() {
          _ended = ended;
          if (_ended) _mediaBusy = false;
          _endedBy = status['ended_by'] as String?;
          _currentEndedAt = DateTime.tryParse('${status['ended_at'] ?? ''}');
          _statusLoading = false;
          _statusError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusLoading = false;
          _statusError = 'Could not check conversation status.';
        });
      }
    }
  }

  Future<void> _endChat() async {
    if (_ending || _ended || _statusLoading || _statusError != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MaakColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _dangerTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble_outline, color: _dangerColor),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('End conversation?')),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You and your peer will no longer be able to send messages. '
              'Your chat history will remain available.',
            ),
            SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _dangerColor, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reopening this conversation requires your peer’s approval.',
                    style: TextStyle(
                      color: _dangerColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep chatting'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: _dangerColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('End chat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _ending = true);
    try {
      await SupabaseService.endChat(widget.requestId);
      if (mounted) {
        setState(() {
          _ended = true;
          _mediaBusy = false;
          _endedBy = SupabaseService.currentUser?.id;
          _currentEndedAt = DateTime.now().toUtc();

          _sendError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not end conversation. Please try again.'),
          ),
        );
      }
      await _loadStatus();
    } finally {
      if (mounted) {
        setState(() => _ending = false);
      }
    }
  }

  Future<void> _requestReopen() async {
    if (_reopenBusy || !_ended || _endedBy != SupabaseService.currentUser?.id) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.mark_chat_unread_outlined,
              color: Color(0xFFD97883),
              size: 28,
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Request to reopen chat?')),
          ],
        ),
        content: const Text(
          'Your peer must agree before either of you can send messages again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF60575A),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD97883),
              foregroundColor: Colors.white,
            ),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _reopenBusy = true);
    Object? requestError;
    try {
      await SupabaseService.requestChatReopen(widget.requestId);
    } catch (e) {
      requestError = e;
    }

    if (!mounted) return;
    setState(() => _reopenBusy = false);
    // Refresh regardless of the RPC response: a timed-out response may still
    // have committed in the database. Never show a misleading failure first.
    try {
      await _fetchReopenRequests();
    } catch (_) {
      // The periodic refresh will retry. Keep the last successful data.
    }
    if (!mounted) return;
    _refreshReopenRequests();

    final currentAttempts = _lastReopenRequests.where((row) {
      final created = DateTime.tryParse('${row['created_at'] ?? ''}');
      return _currentEndedAt != null &&
          created != null &&
          !created.isBefore(_currentEndedAt!);
    }).toList();
    final committed = currentAttempts.any(
      (row) =>
          row['requested_by'] == SupabaseService.currentUser?.id &&
          row['status'] == 'pending',
    );
    if (requestError == null || committed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reopen request sent. Waiting for your peer’s response.',
          ),
        ),
      );
    } else {
      final message = requestError.toString();
      if (message.contains('reopen_request_pending') ||
          message.contains('23505')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A reopen request is still pending. Please wait for your peer’s response.',
            ),
          ),
        );
      } else if (message.contains('reopen_request_limit_reached')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You’ve reached the maximum of 3 reopen requests for this closure.',
            ),
          ),
        );
      } else {
        showAppError(context, requestError);
      }
    }
  }

  Future<void> _decideReopen(bool accept) async {
    if (_reopenBusy || !_ended) return;
    if (accept) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reopen this conversation?'),
          content: const Text(
            'If you agree, both participants can send messages again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep closed'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reopen chat'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() => _reopenBusy = true);
    Object? decisionError;
    try {
      await SupabaseService.decideChatReopen(widget.requestId, accept: accept);
    } catch (e) {
      decisionError = e;
    }
    if (!mounted) return;
    setState(() => _reopenBusy = false);

    // Check the authoritative state, even if the RPC response was interrupted.
    bool? actuallyReopened;
    try {
      final row = await SupabaseService.client
          .from('support_requests')
          .select('ended_at')
          .eq('id', widget.requestId)
          .single();
      actuallyReopened = row['ended_at'] == null;
    } catch (_) {
      // Do not mislabel a successful decision due to a refresh failure.
    }
    if (!mounted) return;
    _refreshReopenRequests();
    try {
      await _loadStatus();
    } catch (_) {
      // The existing status stream will also update the conversation.
    }
    if (!mounted) return;
    if (decisionError == null || (accept && actuallyReopened == true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Conversation reopened.' : 'Request declined.',
          ),
        ),
      );
    } else {
      showAppError(context, decisionError);
    }
  }

  Widget _reopenControls() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _reopenFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError && _lastReopenRequests.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Unable to refresh reopen requests. Retrying automatically.',
              ),
              TextButton(
                onPressed: _refreshReopenRequests,
                child: const Text('Retry now'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData && _lastReopenRequests.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        );
      }
      final requests = snapshot.data ?? _lastReopenRequests;
      final pending = requests.where((row) => row['status'] == 'pending');
      if (pending.isNotEmpty) {
        final request = pending.first;
        final mine = request['requested_by'] == SupabaseService.currentUser?.id;
        if (mine) {
          final attempts = requests.where((row) {
            final created = DateTime.tryParse('${row['created_at'] ?? ''}');
            return _currentEndedAt != null &&
                created != null &&
                !created.isBefore(_currentEndedAt!);
          }).length;
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Reopen requests: $attempts of 3'),
                const SizedBox(height: 6),
                const Text(
                  'Reopen request pending your peer’s approval.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        if (request['recipient_id'] == SupabaseService.currentUser?.id) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text(
                  'Your peer wants to reopen this conversation.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB54747),
                        side: const BorderSide(color: Color(0xFFB54747)),
                      ),
                      onPressed: _reopenBusy
                          ? null
                          : () => _decideReopen(false),
                      icon: const Icon(Icons.close),
                      label: const Text('Decline'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF287A57),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _reopenBusy ? null : () => _decideReopen(true),
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Accept & reopen'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
      }
      // Only count requests created after the current closure.
      // A new End Chat resets the allowance to 3.
      final endedAt = _ended ? _currentEndedAt : null;
      final closureRequests = requests.where((row) {
        final created = DateTime.tryParse('${row['created_at'] ?? ''}');
        return endedAt != null && created != null && !created.isBefore(endedAt);
      }).toList();
      final attempts = closureRequests.length;
      if (attempts >= 3) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Reopen requests: 3 of 3', textAlign: TextAlign.center),
              SizedBox(height: 6),
              Text(
                'You’ve reached the maximum of 3 reopen requests for this closure.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }
      if (_endedBy != SupabaseService.currentUser?.id) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Only the person who ended the conversation can request to reopen it.',
            textAlign: TextAlign.center,
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reopen requests: $attempts of 3'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _reopenBusy ? null : _requestReopen,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97883),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(
                _reopenBusy ? 'Please wait...' : 'Request to reopen chat',
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _react(String messageId, String emoji) async {
    if (_ended || _statusLoading || _statusError != null) return;
    try {
      await SupabaseService.toggleChatReaction(
        widget.requestId,
        messageId,
        emoji,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reaction could not be saved. Please try again.'),
          ),
        );
      }
    }
  }

  void _showReactions(String messageId) {
    if (_ended || _statusLoading || _statusError != null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'React to message',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['❤️', '👍', '😊', '🙏', '💗']
                    .map(
                      (emoji) => Semantics(
                        label: 'React with $emoji',
                        button: true,
                        child: IconButton(
                          tooltip: 'React with $emoji',
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _react(messageId, emoji);
                          },
                          icon: Text(
                            emoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _deletingMessage = false;
  bool _messageMenuOpen = false;
  Future<void> _messageOptions(Map<String, dynamic> message) async {
    if (_deletingMessage || _messageMenuOpen) return;
    _messageMenuOpen = true;
    try {
      final mine = message['sender_id'] == SupabaseService.userId;
      final deleted = message['deleted_at'] != null;
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Message options',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (!deleted && !_ended)
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined),
                  title: const Text('React'),
                  onTap: () => Navigator.pop(context, 'react'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete for me'),
                subtitle: const Text('The other person keeps this message.'),
                onTap: () => Navigator.pop(context, 'me'),
              ),
              if (mine && !deleted)
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: _dangerColor,
                  ),
                  title: const Text(
                    'Delete for everyone',
                    style: TextStyle(color: _dangerColor),
                  ),
                  subtitle: const Text(
                    'Remove your message for both participants.',
                  ),
                  onTap: () => Navigator.pop(context, 'everyone'),
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'react') {
        _showReactions(message['id'].toString());
        return;
      }
      final everyone = action == 'everyone';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.delete_outline, color: _dangerColor, size: 32),
          title: Text(everyone ? 'Delete for everyone?' : 'Delete for you?'),
          content: Text(
            everyone
                ? 'Are you sure you want to delete this message for both participants? This cannot be undone.'
                : 'Are you sure you want to delete this message from your account? The other person will still have it. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _dangerColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(everyone ? 'Delete for everyone' : 'Delete for me'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _deletingMessage = true);
      try {
        await SupabaseService.deleteMessage(
          message['id'].toString(),
          forEveryone: everyone,
        );
        if (mounted)
          showSuccess(
            context,
            everyone
                ? 'Message deleted for everyone.'
                : 'Message deleted for you.',
          );
      } catch (error) {
        if (mounted) showAppError(context, error);
      } finally {
        if (mounted) setState(() => _deletingMessage = false);
      }
    } finally {
      _messageMenuOpen = false;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty ||
        _busy ||
        _mediaBusy ||
        _ended ||
        _statusLoading ||
        _statusError != null ||
        text.length > 2000) {
      return;
    }
    setState(() {
      _busy = true;
      _sendError = null;
    });
    try {
      await SupabaseService.sendMessage(widget.requestId, text);
      if (mounted && _input.text.trim() == text) {
        _input.clear();
      }
    } catch (_) {
      await _loadStatus();
      if (mounted && !_ended) {
        setState(
          () => _sendError =
              'Message not sent. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _time(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Conversation options',
          enabled:
              !_ended && !_ending && !_statusLoading && _statusError == null,
          onSelected: (value) {
            if (value == 'end') _endChat();
          },
          itemBuilder: (_) => const [
            PopupMenuItem<String>(
              value: 'end',
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    color: _dangerColor,
                    size: 22,
                  ),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'End chat',
                        style: TextStyle(
                          color: _dangerColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Close this conversation',
                        style: TextStyle(fontSize: 12, color: MaakColors.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          const Text(
            'Private conversation',
            style: TextStyle(fontSize: 12, color: MaakColors.muted),
          ),
        ],
      ),
    ),
    body: ResponsiveBody(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: MaakColors.blush,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 17, color: MaakColors.muted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Peer support is not medical advice.',
                    style: TextStyle(fontSize: 12, color: MaakColors.muted),
                  ),
                ),
              ],
            ),
          ),
          if (_statusError != null)
            MaterialBanner(
              content: Text(_statusError!),
              actions: [
                TextButton(onPressed: _loadStatus, child: const Text('Retry')),
              ],
            ),
          if (_ended)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                color: _endedTint,
                border: Border(bottom: BorderSide(color: Color(0xFFE8D7DD))),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 22, color: _dangerColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conversation ended',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _dangerColor,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Chat history is available in read-only mode.',
                          style: TextStyle(fontSize: 12, color: MaakColors.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_ended) _reopenControls(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    'Could not load conversation',
                    friendlyError(snapshot.error!),
                    retry: () => setState(
                      () => _stream = SupabaseService.messageStream(
                        widget.requestId,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = chronologicalMessages(snapshot.data!);
                if (messages.isEmpty) {
                  return const EmptyState(
                    'Say hello',
                    'Start your conversation with a kind message.',
                    icon: Icons.chat_bubble_outline,
                  );
                }
                final last = messages.last['id']?.toString();
                final nearBottom =
                    !_scroll.hasClients || _scroll.position.extentAfter < 100;
                if (_lastMessageId != last) {
                  _lastMessageId = last;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _scroll.hasClients && nearBottom) {
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    }
                  });
                }
                final unread = messages
                    .where(
                      (m) =>
                          m['sender_id'] != SupabaseService.userId &&
                          m['read_at'] == null &&
                          m['deleted_at'] == null,
                    )
                    .map((m) => m['id'] as String)
                    .toList();
                if (!_reading &&
                    unread.isNotEmpty &&
                    ModalRoute.of(context)?.isCurrent == true &&
                    WidgetsBinding.instance.lifecycleState ==
                        AppLifecycleState.resumed) {
                  _reading = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    try {
                      if (mounted &&
                          ModalRoute.of(context)?.isCurrent == true) {
                        await SupabaseService.markMessagesRead(
                          widget.requestId,
                          unread,
                        );
                      }
                    } catch (_) {
                      // Leave unread status intact if acknowledgement fails.
                    } finally {
                      _reading = false;
                    }
                  });
                }
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _reactionsStream,
                  builder: (context, reactionSnapshot) {
                    final reactions =
                        reactionSnapshot.data ?? const <Map<String, dynamic>>[];
                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        final me = m['sender_id'] == SupabaseService.userId;
                        final currentDate = DateTime.tryParse(
                          m['created_at']?.toString() ?? '',
                        )?.toLocal();
                        final previousDate = index == 0
                            ? null
                            : DateTime.tryParse(
                                messages[index - 1]['created_at']?.toString() ??
                                    '',
                              )?.toLocal();
                        final showDate =
                            currentDate != null &&
                            (previousDate == null ||
                                currentDate.year != previousDate.year ||
                                currentDate.month != previousDate.month ||
                                currentDate.day != previousDate.day);
                        final previousSameSender =
                            index > 0 &&
                            messages[index - 1]['sender_id'] ==
                                m['sender_id'] &&
                            !showDate;
                        return Column(
                          children: [
                            if (showDate)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Text(
                                  _dateLabel(currentDate),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: MaakColors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Align(
                              alignment: me
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * .76,
                                ),
                                child: Column(
                                  crossAxisAlignment: me
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onLongPress: () => _messageOptions(m),
                                      child: Container(
                                        margin: EdgeInsets.only(
                                          top: previousSameSender ? 3 : 12,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: me
                                              ? MaakColors.selected
                                              : Colors.white,
                                          border: Border.all(
                                            color: me
                                                ? MaakColors.selected
                                                : MaakColors.border,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: m['deleted_at'] != null
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.block,
                                                    color: MaakColors.muted,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      m['body']?.toString() ??
                                                          'This message was deleted.',
                                                      style: const TextStyle(
                                                        color: MaakColors.muted,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : m['message_type'] == 'image' ||
                                                  m['message_type'] ==
                                                      'voice' ||
                                                  m['message_type'] == 'video'
                                            ? ChatMediaBubble(
                                                key: ValueKey(m['id']),
                                                message: m,
                                              )
                                            : Text(
                                                m['body']?.toString() ?? '',
                                                style: const TextStyle(
                                                  color: MaakColors.ink,
                                                  fontSize: 14,
                                                  height: 1.4,
                                                ),
                                              ),
                                      ),
                                    ),
                                    if (m['deleted_at'] == null &&
                                        reactions.any(
                                          (r) => r['message_id'] == m['id'],
                                        ))
                                      Wrap(
                                        spacing: 4,
                                        children: [
                                          for (final emoji in [
                                            '❤️',
                                            '👍',
                                            '😊',
                                            '🙏',
                                            '💗',
                                          ])
                                            if (reactions.any(
                                              (r) =>
                                                  r['message_id'] == m['id'] &&
                                                  r['emoji'] == emoji,
                                            ))
                                              ActionChip(
                                                tooltip: 'React with $emoji',
                                                label: Text(
                                                  '$emoji ${reactions.where((r) => r['message_id'] == m['id'] && r['emoji'] == emoji).length}',
                                                ),
                                                onPressed: _ended
                                                    ? null
                                                    : () => _react(
                                                        m['id'].toString(),
                                                        emoji,
                                                      ),
                                              ),
                                        ],
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        left: 5,
                                        right: 5,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (m['deleted_at'] != null)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                right: 4,
                                              ),
                                              child: Icon(
                                                Icons.block,
                                                size: 12,
                                                color: MaakColors.muted,
                                              ),
                                            ),
                                          Text(
                                            _time(m['created_at']),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: MaakColors.muted,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          SizedBox(
                                            width: 40,
                                            height: 40,
                                            child: IconButton(
                                              tooltip:
                                                  'Message options · Delete',
                                              onPressed: _deletingMessage
                                                  ? null
                                                  : () => _messageOptions(m),
                                              icon: const Icon(
                                                Icons.more_horiz,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: const BoxDecoration(
                color: MaakColors.surface,
                border: Border(top: BorderSide(color: MaakColors.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_ended)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: MaakColors.muted,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Chat ended — you can no longer send messages.',
                              style: TextStyle(color: MaakColors.muted),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_ended)
                    ChatMediaComposer(
                      key: ValueKey(widget.requestId),
                      requestId: widget.requestId,
                      enabled:
                          !_busy &&
                          !_ending &&
                          !_statusLoading &&
                          _statusError == null,
                      onBusy: (value) {
                        if (mounted) setState(() => _mediaBusy = value);
                      },
                    ),
                  if (!_ended && _sendError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: MaakColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _sendError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: MaakColors.error,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _send,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  if (!_ended)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            enabled:
                                !_statusLoading &&
                                _statusError == null &&
                                !_busy,
                            maxLength: 2000,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Write a message...',
                              counterText: '',
                              filled: true,
                              fillColor: MaakColors.blush,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(
                                  color: MaakColors.border,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed:
                              _busy ||
                                  _statusLoading ||
                                  _statusError != null ||
                                  _mediaBusy ||
                                  _input.text.trim().isEmpty
                              ? null
                              : _send,
                          tooltip: 'Send message',
                          style: IconButton.styleFrom(
                            backgroundColor: _sendColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: MaakColors.fill,
                            disabledForegroundColor: MaakColors.muted,
                          ),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class JourneyPage extends StatefulWidget {
  const JourneyPage({super.key});
  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = SupabaseService.getRequests();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = SupabaseService.getRequests();
      });
    }
  }

  Future<void> _findMatches() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MatchingPage()),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) => MaakPage(
    title: 'My journey',
    onRefresh: () async {
      _reload();
      await _future;
    },
    children: (context, wide) => [
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, s) {
          if (s.hasError) {
            return StateMessage(
              title: 'Could not load data',
              message: friendlyError(s.error!),
              icon: Icons.cloud_off_outlined,
              retry: _reload,
            );
          }
          if (!s.hasData) {
            return const ListSkeleton(
              label: 'Loading your requests',
              height: 132,
            );
          }
          if (s.data!.isEmpty) return _EmptyJourney(onFind: _findMatches);
          // Open requests first; declined and canceled ones are history.
          bool open(Map<String, dynamic> r) =>
              r['status'] == 'pending' || r['status'] == 'accepted';
          final groups = {
            'Active': s.data!.where(open).toList(),
            'Past': s.data!.where((r) => !open(r)).toList(),
          }..removeWhere((_, rows) => rows.isEmpty);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, group) in groups.entries.indexed) ...[
                SectionHeader(group.key, top: i == 0 ? 0 : MaakSpace.xxl),
                _cards([
                  for (final row in group.value)
                    _RequestCard(
                      request: row,
                      reload: _reload,
                      past: group.key == 'Past',
                    ),
                ], wide),
              ],
            ],
          );
        },
      ),
    ],
  );

  Widget _cards(List<Widget> cards, bool wide) => wide
      ? PairedGrid(children: cards)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, card) in cards.indexed) ...[
              if (i > 0) const SizedBox(height: MaakSpace.md),
              card,
            ],
          ],
        );
}

class _EmptyJourney extends StatelessWidget {
  final VoidCallback onFind;
  const _EmptyJourney({required this.onFind});
  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.symmetric(
      horizontal: MaakSpace.xl,
      vertical: MaakSpace.xxxl - 4,
    ),
    child: Column(
      children: [
        const IconBadge(Icons.people_outline, size: 56),
        const SizedBox(height: MaakSpace.lg),
        const Text(
          'Your journey starts here',
          textAlign: TextAlign.center,
          style: MaakText.section,
        ),
        const SizedBox(height: MaakSpace.xs),
        const Text(
          'Find a volunteer to take the next step.',
          textAlign: TextAlign.center,
          style: MaakText.body,
        ),
        const SizedBox(height: MaakSpace.xl),
        PillButton(
          'Find my matches',
          icon: Icons.arrow_forward,
          onPressed: onFind,
        ),
      ],
    ),
  );
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback reload;
  final bool past;
  const _RequestCard({
    required this.request,
    required this.reload,
    required this.past,
  });
  @override
  Widget build(BuildContext context) {
    final status = request['status'];
    final name = request['contact_name'] as String? ?? 'Volunteer';
    final sent = formatDay(request['created_at'] as String?);
    final (label, icon, color) = switch (status) {
      'pending' => ('Awaiting response', Icons.schedule, MaakColors.blush),
      'accepted' => ('Connected', Icons.check, MaakColors.selected),
      'canceled' => ('Canceled', Icons.block, MaakColors.fill),
      _ => ('Declined', Icons.close, MaakColors.fill),
    };
    return SoftCard(
      flat: past,
      color: past ? MaakColors.warmWhite : MaakColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(initials(name)),
              const SizedBox(width: MaakSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: MaakText.itemTitle),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: MaakSpace.sm,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(label: label, icon: icon, color: color),
                        if (sent.isNotEmpty)
                          Text('Sent $sent', style: MaakText.caption),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MaakSpace.md),
          Text(
            status == 'accepted'
                ? 'You can now message your volunteer.'
                : 'Your support request has been recorded.',
            style: MaakText.body.copyWith(fontSize: 13),
          ),
          if (status == 'pending') ...[
            const SizedBox(height: MaakSpace.md),
            CancelRequestButton(
              requestId: request['id'] as String,
              onDone: reload,
            ),
          ],
          if (status == 'accepted') ...[
            const SizedBox(height: MaakSpace.md),
            PillButton(
              'Open conversation',
              icon: Icons.chat_bubble_outline,
              compact: true,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConversationPage(
                    requestId: request['id'] as String,
                    name: name,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
// اضافه جديده

class CancelRequestButton extends StatefulWidget {
  final String requestId;
  final VoidCallback onDone;
  const CancelRequestButton({
    super.key,
    required this.requestId,
    required this.onDone,
  });
  @override
  State<CancelRequestButton> createState() => _CancelRequestButtonState();
}

class _CancelRequestButtonState extends State<CancelRequestButton> {
  bool _busy = false;
  Future<void> _cancel() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MaakColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cancel this request?', style: MaakText.cardTitle),
        content: const Text(
          'The volunteer will be notified.',
          style: MaakText.body,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          MaakSpace.xl,
          0,
          MaakSpace.xl,
          MaakSpace.xl,
        ),
        actions: [
          PillButton(
            'Keep request',
            outlined: true,
            compact: true,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          PillButton(
            'Cancel request',
            compact: true,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await SupabaseService.cancelRequest(widget.requestId);
      if (!mounted) return;
      showSuccess(context, 'Request canceled.');
      widget.onDone();
    } catch (e) {
      if (mounted) showAppError(context, e, retry: _cancel);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PillButton(
    _busy ? 'Canceling...' : 'Cancel request',
    outlined: true,
    compact: true,
    onPressed: _busy ? null : _cancel,
  );
}
// هنا تنتهي

class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Resources',
    load: SupabaseService.getResources,
    emptyTitle: 'No resources published yet',
    emptyText: 'Resources added by your team will appear here.',
    item: (context, row, reload) => SurfaceCard(
      onTap: () async {
        try {
          final url = Uri.tryParse(row['url'] as String);
          if (url == null || url.scheme != 'https') {
            throw ArgumentError('Invalid resource link.');
          }
          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
            throw StateError('Could not open link');
          }
        } catch (e) {
          if (context.mounted) showAppError(context, e);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.description_outlined, color: AppColors.primaryNavy),
          const SizedBox(height: 12),
          Text(
            row['title'] as String,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            row['summary'] as String,
            style: const TextStyle(color: AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Read resource →',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

String formatDate(String date) {
  final d = DateTime.parse(date).toLocal();
  final minutes = d.minute.toString().padLeft(2, '0');
  final hour = d.hour == 0
      ? 12
      : d.hour > 12
      ? d.hour - 12
      : d.hour;
  return '${d.day}/${d.month}/${d.year} · $hour:$minutes ${d.hour >= 12 ? 'PM' : 'AM'}';
}
