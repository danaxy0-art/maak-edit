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
      if (mounted) setState(() => _busy = false);
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
      if (mounted)
        showSuccess(
          context,
          'Decision saved. Reopen this page to refresh the list.',
        );
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
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _lastMessageId;
  bool _reading = false;
  late Stream<List<Map<String, dynamic>>> _stream;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = SupabaseService.messageStream(widget.requestId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final text = _input.text;
    try {
      await SupabaseService.sendMessage(widget.requestId, text);
      if (mounted && _input.text == text) _input.clear();
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: ResponsiveBody(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.selectedCardFill,
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Peer support is not medical advice.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, s) {
                if (s.hasError) {
                  return EmptyState(
                    'Could not load conversation',
                    friendlyError(s.error!),
                    retry: () => setState(
                      () => _stream = SupabaseService.messageStream(
                        widget.requestId,
                      ),
                    ),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.data!.isEmpty) {
                  return const EmptyState(
                    'Say hello',
                    'Start your conversation with a kind message.',
                    icon: Icons.chat_bubble_outline,
                  );
                }
                final messages = chronologicalMessages(s.data!);
                final last = messages.last['id'] as String;
                final nearBottom =
                    !_scroll.hasClients || _scroll.position.extentAfter < 100;
                if (_lastMessageId != last) {
                  _lastMessageId = last;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _scroll.hasClients && nearBottom)
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  });
                }
                final unread = messages
                    .where(
                      (m) =>
                          m['sender_id'] != SupabaseService.userId &&
                          m['read_at'] == null,
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
                      if (mounted && ModalRoute.of(context)?.isCurrent == true)
                        await SupabaseService.markMessagesRead(
                          widget.requestId,
                          unread,
                        );
                    } catch (_) {
                      // Keep unread counts intact if acknowledgement fails.
                    } finally {
                      _reading = false;
                    }
                  });
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: false,
                  padding: const EdgeInsets.all(18),
                  itemCount: s.data!.length,
                  itemBuilder: (context, i) {
                    final m = messages[i],
                        me = m['sender_id'] == SupabaseService.userId;
                    return Align(
                      alignment: me
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .72,
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: me ? AppColors.primaryNavy : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: me
                              ? null
                              : Border.all(color: AppColors.divider),
                        ),
                        child: Text(
                          m['body'] as String,
                          style: TextStyle(
                            color: me ? Colors.white : AppColors.textDark,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a message...',
                      ),
                      enabled: !_busy,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    tooltip: 'Send message',
                    icon: const Icon(Icons.send_outlined),
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
