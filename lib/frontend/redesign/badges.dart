import 'package:flutter/material.dart';

import '../../backend/services/volunteer_stats_service.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import 'feedback.dart';

// Volunteer participation badges (Sprint 4 US3, US4). The level is derived in
// the database (20261126110000_volunteer_badges.sql); this only displays it.

/// Shown next to badges so "Expert" is not read as a medical qualification.
const badgeMeaning =
    'Badges count the help seekers a volunteer has supported on Ma\'ak. They are not a medical qualification.';

/// Colours and icon per level. Text always carries the level, so colour is
/// never the only cue; each pair keeps at least 4.5:1 contrast.
({Color background, Color foreground, IconData icon}) _look(BadgeLevel level) =>
    switch (level) {
      BadgeLevel.beginner => (
        background: const Color(0xFFFDECDC),
        foreground: MaakColors.ink,
        icon: Icons.eco_outlined,
      ),
      BadgeLevel.intermediate => (
        background: MaakColors.selected,
        foreground: MaakColors.ink,
        icon: Icons.volunteer_activism_outlined,
      ),
      BadgeLevel.expert => (
        background: const Color(0xFFA63E4B),
        foreground: Colors.white,
        icon: Icons.workspace_premium_outlined,
      ),
    };

/// "Intermediate badge" pill with its icon.
class BadgeChip extends StatelessWidget {
  final BadgeLevel level;
  const BadgeChip(this.level, {super.key});
  @override
  Widget build(BuildContext context) {
    final look = _look(level);
    return Tooltip(
      message: badgeMeaning,
      child: Semantics(
        label: '${level.label} participation badge',
        excludeSemantics: true,
        child: Container(
          key: ValueKey('badge_${level.name}'),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 10, 4),
          decoration: BoxDecoration(
            color: look.background,
            borderRadius: BorderRadius.circular(MaakRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(look.icon, size: 15, color: look.foreground),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${level.label} badge',
                  overflow: TextOverflow.ellipsis,
                  style: MaakText.caption.copyWith(
                    color: look.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The signed-in volunteer's badge and progress to the next one, for their
/// own profile. Shows nothing for other members.
class MyBadgeProgressCard extends StatefulWidget {
  /// Test hook; defaults to the server.
  final Future<BadgeProgress?> Function()? load;
  const MyBadgeProgressCard({super.key, this.load});
  @override
  State<MyBadgeProgressCard> createState() => _MyBadgeProgressCardState();
}

class _MyBadgeProgressCardState extends State<MyBadgeProgressCard> {
  late Future<BadgeProgress?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<BadgeProgress?> _fetch() =>
      (widget.load ?? VolunteerStatsService.myBadgeProgress)();

  // Block body: an arrow would hand the new Future to setState.
  void _retry() => setState(() {
    _future = _fetch();
  });

  static String _people(int n) => n == 1 ? '1 help seeker' : '$n help seekers';

  @override
  Widget build(BuildContext context) => FutureBuilder<BadgeProgress?>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _card(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Could not load your badge. ${friendlyError(snapshot.error!)}',
                  style: MaakText.caption,
                ),
              ),
              TextButton(onPressed: _retry, child: const Text('Retry')),
            ],
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return Padding(
          padding: const EdgeInsets.only(bottom: MaakSpace.md),
          child: Semantics(
            label: 'Loading your badge',
            child: SkeletonBlock(height: 72),
          ),
        );
      }
      final p = snapshot.data;
      if (p == null) return const SizedBox.shrink();
      final badge = p.badge, next = p.next, nextMin = p.nextMin;
      final String status;
      if (next == null || nextMin == null) {
        status =
            'You have supported ${_people(p.supported)}. This is the highest badge.';
      } else {
        final left = nextMin - p.supported;
        status =
            'You have supported ${_people(p.supported)}. ${left == 1 ? '1 more' : '$left more'} to earn the ${next.label} badge.';
      }
      return _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'My participation badge',
                    style: MaakText.itemTitle,
                  ),
                ),
                if (badge != null) BadgeChip(badge),
              ],
            ),
            const SizedBox(height: MaakSpace.xs),
            Text(
              badge == null
                  ? 'No badge yet. Support your first help seeker to earn the Beginner badge.'
                  : status,
              key: const ValueKey('badge_progress_text'),
              style: MaakText.caption.copyWith(color: MaakColors.ink),
            ),
            if (next != null && nextMin != null) ...[
              const SizedBox(height: MaakSpace.sm),
              Semantics(
                container: true,
                label:
                    'Progress to the ${next.label} badge: ${p.supported} of $nextMin help seekers supported',
                excludeSemantics: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(MaakRadius.pill),
                  child: LinearProgressIndicator(
                    value: (p.supported / nextMin).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    color: const Color(0xFFC24D5A),
                    backgroundColor: MaakColors.fill,
                  ),
                ),
              ),
            ],
            const SizedBox(height: MaakSpace.sm),
            Text(
              '$badgeMeaning Each help seeker counts once, when a conversation with them has ended with a reply from you, and still counts if it is reopened.',
              style: MaakText.caption.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
    },
  );

  Widget _card(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: MaakSpace.md),
    child: SoftCard(
      key: const ValueKey('my_badge_card'),
      padding: const EdgeInsets.all(MaakSpace.md),
      child: child,
    ),
  );
}
