import 'profile.dart';
import 'matching_page.dart';

import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../widgets/user_photo.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../widgets/current_user_name.dart';
import '../widgets/maak_logo.dart';
import 'ui.dart';
import 'notifications.dart';
import 'navigation.dart';
import 'support.dart';
import 'feedback.dart';

class HomePage extends StatefulWidget {
  final String role;
  const HomePage({super.key, required this.role});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<List<Map<String, dynamic>>>> _future;
  bool get volunteer => widget.role == 'volunteer';
  @override
  void initState() {
    super.initState();
    _load();
  }

  // A block body on purpose: an arrow body would hand the Future to
  // setState(_load), which Flutter rejects in debug builds.
  void _load() {
    _future = Future.wait([SupabaseService.getRequests()]);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MaakColors.canvasMid,
    body: BlushCanvas(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: MaakColors.ink,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= MaakBreakpoints.tablet;
              final gutter = wide ? MaakSpace.xxl : MaakSpace.lg;
              return ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  gutter,
                  MaakSpace.sm,
                  gutter,
                  MaakSpace.xxxl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: wide
                            ? MaakBreakpoints.tabletMaxContent
                            : MaakBreakpoints.phoneMaxContent,
                      ),
                      child: FutureBuilder<List<List<Map<String, dynamic>>>>(
                        future: _future,
                        builder: (context, s) => wide ? _tablet(s) : _phone(s),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _phone(AsyncSnapshot<List<List<Map<String, dynamic>>>> s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(),
      const SizedBox(height: MaakSpace.xl),
      _greeting(),
      const SizedBox(height: MaakSpace.xl),
      _hero(),
      if (volunteer) ...[const SizedBox(height: MaakSpace.lg), _activity(s)],
      const SectionHeader('Quick actions'),
      for (final (i, action) in _actions().indexed) ...[
        if (i > 0) const SizedBox(height: MaakSpace.sm),
        action,
      ],
      if (!volunteer) ...[
        const SectionHeader('Recent conversation'),
        _activity(s),
      ],
    ],
  );

  // Two connected rows: the main action beside the member's activity, then
  // the shortcuts across the full width so neither column runs short.
  Widget _tablet(AsyncSnapshot<List<List<Map<String, dynamic>>>> s) {
    final actions = _actions(stacked: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: MaakSpace.xxxl),
        _greeting(large: true),
        const SizedBox(height: MaakSpace.xxxl),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: _hero(large: true)),
              const SizedBox(width: MaakSpace.xl),
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      volunteer ? 'Your activity' : 'Recent conversation',
                      top: 0,
                    ),
                    Expanded(child: _activity(s)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Quick actions', top: MaakSpace.xxxl),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, action) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: MaakSpace.md),
                Expanded(child: action),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() => const Row(
    children: [
      MaakLogo(iconSize: 24, tint: MaakGradients.coral),
      Spacer(),
      RoundIconSurface(child: NotificationBell()),
    ],
  );

  Widget _greeting({bool large = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: CurrentUserName(
              prefix: 'Hello, ',
              style: large
                  ? MaakText.greeting.copyWith(fontSize: 34)
                  : MaakText.greeting,
            ),
          ),
          if (volunteer) const SoftChip('Volunteer'),
        ],
      ),
      const SizedBox(height: MaakSpace.xs),
      Text(
        volunteer
            ? 'Thank you for being here.'
            : 'You’re not alone on this journey.',
        style: MaakText.body,
      ),
    ],
  );

  Widget _hero({bool large = false}) => GlowActionCard(
    large: large,
    title: volunteer
        ? 'Your experience can make a difference.'
        : 'Support from someone who understands.',
    subtitle: volunteer
        ? 'Be there for someone who understands.'
        : 'Connect with a volunteer who has a similar experience.',
    action: volunteer ? 'Matching preferences' : 'Find my matches',
    onPressed: () => _push(
      volunteer
          ? const EditProfilePage(role: 'volunteer')
          : const MatchingPage(),
    ),
  );

  List<Widget> _actions({bool stacked = false}) => [
    if (volunteer)
      ActionRow(
        icon: Icons.people_outline,
        title: 'Requests',
        subtitle: 'View and respond',
        stacked: stacked,
        onTap: () => _push(const RequestsPage()),
      )
    else
      ActionRow(
        icon: Icons.book_outlined,
        title: 'My journey',
        subtitle: 'Track your progress',
        stacked: stacked,
        onTap: () => ShellScope.maybeOf(context)?.selectTab(1),
      ),
    ActionRow(
      icon: Icons.chat_bubble_outline,
      title: 'Messages',
      subtitle: 'Your conversations',
      stacked: stacked,
      onTap: () => ShellScope.maybeOf(context)?.selectTab(2),
    ),
    ActionRow(
      icon: Icons.description_outlined,
      title: 'Resources',
      subtitle: 'Helpful information',
      stacked: stacked,
      onTap: () => _push(const ResourcesPage()),
    ),
  ];

  /// Help seekers: their latest conversation. Volunteers: request counts.
  Widget _activity(AsyncSnapshot<List<List<Map<String, dynamic>>>> s) {
    if (s.hasError) {
      return StateMessage(
        title: 'Could not load your activity',
        message: friendlyError(s.error!),
        icon: Icons.cloud_off_outlined,
        retry: () => setState(_load),
      );
    }
    if (!s.hasData) {
      return Semantics(
        label: 'Loading your activity',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonBlock(height: volunteer ? 112 : 84),
            if (volunteer) ...[
              const SizedBox(height: MaakSpace.md),
              const SkeletonBlock(height: 48),
            ],
          ],
        ),
      );
    }
    final requests = s.data![0];
    final pending = requests.where((r) => r['status'] == 'pending').length;
    final accepted = requests.where((r) => r['status'] == 'accepted').toList();
    if (volunteer) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stats(pending, accepted.length),
          const SizedBox(height: MaakSpace.md),
          PillButton(
            'View requests',
            icon: Icons.arrow_forward,
            outlined: true,
            expand: true,
            onPressed: () => _push(const RequestsPage()),
          ),
        ],
      );
    }
    if (accepted.isEmpty) {
      return const StateMessage(
        message:
            'Your conversations will appear here after a volunteer accepts your request.',
        icon: Icons.chat_bubble_outline,
      );
    }
    final first = accepted.first;
    final name = first['contact_name'] as String? ?? 'Volunteer';
    return PersonPreviewCard(
      userId: otherParticipantId(first),
      initials: initials(first['contact_name'] as String? ?? 'Peer'),
      name: name,
      message:
          first['last_message'] as String? ??
          'Say hello and start your conversation.',
      onTap: () async {
        await ConversationPage.open(
          context,
          requestId: first['id'] as String,
          name: name,
        );
        if (mounted) setState(_load);
      },
    );
  }

  Widget _stats(int pending, int active) {
    const gap = SizedBox(width: MaakSpace.sm, height: MaakSpace.sm);
    final tiles = [
      StatTile(
        label: 'Pending requests',
        value: pending,
        icon: Icons.people_outline,
      ),
      StatTile(
        label: 'Active connections',
        value: active,
        icon: Icons.chat_bubble_outline,
      ),
    ];
    // Side by side the labels get cramped once text is enlarged.
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [tiles[0], gap, tiles[1]],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: tiles[0]),
          gap,
          Expanded(child: tiles[1]),
        ],
      ),
    );
  }
}
