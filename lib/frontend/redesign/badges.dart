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

/// Chip background per level. Text is always ink and always carries the
/// level, so colour is never the only cue (ink on each keeps 4.5:1 or more).
Color _background(BadgeLevel level) => switch (level) {
  BadgeLevel.beginner => const Color(0xFFE6F2DC),
  BadgeLevel.intermediate => const Color(0xFFFDE8D2),
  BadgeLevel.expert => const Color(0xFFFDDDE0),
};

// Ladybug life cycle: worm (Beginner), larva (Intermediate), adult (Expert).
const _wormGreen = Color(0xFF5E9E3E);
const _wormLight = Color(0xFF9CCB6E);
const _bugBlack = Color(0xFF2A2A32);
const _larvaOrange = Color(0xFFF08A24);
const _ladybugRed = Color(0xFFD7263D);

/// The life-cycle stage drawn for a badge level. Decorative: the label next
/// to it names the level.
class BadgeIcon extends StatelessWidget {
  final BadgeLevel level;
  final double size;

  /// Greyed out for a stage not reached yet.
  final bool dimmed;
  const BadgeIcon(this.level, {super.key, this.size = 16, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    Widget icon = CustomPaint(
      size: Size.square(size),
      painter: _LifeCyclePainter(level),
    );
    if (dimmed) {
      icon = Opacity(
        opacity: 0.35,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
          child: icon,
        ),
      );
    }
    return ExcludeSemantics(child: icon);
  }
}

/// Draws on a 24 x 24 grid scaled to the widget size.
class _LifeCyclePainter extends CustomPainter {
  final BadgeLevel level;
  const _LifeCyclePainter(this.level);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    switch (level) {
      case BadgeLevel.beginner:
        _worm(canvas);
      case BadgeLevel.intermediate:
        _larva(canvas);
      case BadgeLevel.expert:
        _ladybug(canvas);
    }
  }

  static Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  static Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  /// A small wriggling green worm.
  static void _worm(Canvas canvas) {
    final body = Path()
      ..moveTo(3.5, 16.5)
      ..cubicTo(7, 9.5, 10.5, 21, 14.5, 13.5);
    canvas.drawPath(body, _stroke(_wormGreen, 5.5));
    // Segment marks.
    for (final p in const [Offset(6.6, 14.6), Offset(10.4, 15.6)]) {
      canvas.drawCircle(p, 0.9, _fill(_wormLight));
    }
    // Head.
    canvas.drawCircle(const Offset(17.2, 11.2), 3.6, _fill(_wormGreen));
    canvas.drawCircle(const Offset(18.3, 10.3), 0.95, _fill(_bugBlack));
  }

  /// The ladybug larva: long dark tapered body, orange spots, six legs.
  static void _larva(Canvas canvas) {
    final legs = _stroke(_bugBlack, 1.3);
    for (final x in const [11.0, 14.5, 17.5]) {
      canvas.drawLine(Offset(x, 9.5), Offset(x + 0.8, 6), legs);
      canvas.drawLine(Offset(x, 14.5), Offset(x + 0.8, 18), legs);
    }
    final body = Path()
      ..moveTo(2.5, 12)
      ..quadraticBezierTo(8, 8.6, 15, 8.3)
      ..quadraticBezierTo(19.5, 8.6, 19.5, 12)
      ..quadraticBezierTo(19.5, 15.4, 15, 15.7)
      ..quadraticBezierTo(8, 15.4, 2.5, 12)
      ..close();
    canvas.drawPath(body, _fill(_bugBlack));
    canvas.drawCircle(const Offset(20.6, 12), 2.3, _fill(_bugBlack));
    final spot = _fill(_larvaOrange);
    canvas.drawCircle(const Offset(8.5, 12), 1.2, spot);
    canvas.drawCircle(const Offset(13.5, 10.4), 1.15, spot);
    canvas.drawCircle(const Offset(13.5, 13.6), 1.15, spot);
  }

  /// The adult ladybug: red shell, black spots, head and antennae.
  static void _ladybug(Canvas canvas) {
    final dark = _stroke(_bugBlack, 1.3);
    // Antennae and legs.
    canvas.drawLine(const Offset(10.8, 3.6), const Offset(8.6, 1.2), dark);
    canvas.drawLine(const Offset(13.2, 3.6), const Offset(15.4, 1.2), dark);
    for (final y in const [10.5, 14.0, 17.5]) {
      canvas.drawLine(Offset(6, y), Offset(2.6, y + 0.8), dark);
      canvas.drawLine(Offset(18, y), Offset(21.4, y + 0.8), dark);
    }
    // Head.
    canvas.drawCircle(const Offset(12, 6), 3.4, _fill(_bugBlack));
    canvas.drawCircle(const Offset(10.7, 5.2), 0.65, _fill(Colors.white));
    canvas.drawCircle(const Offset(13.3, 5.2), 0.65, _fill(Colors.white));
    // Shell, wing split and spots.
    canvas.drawCircle(const Offset(12, 14), 7.8, _fill(_ladybugRed));
    canvas.drawLine(const Offset(12, 6.6), const Offset(12, 21.6), dark);
    final spot = _fill(_bugBlack);
    canvas.drawCircle(const Offset(8.6, 11.4), 1.6, spot);
    canvas.drawCircle(const Offset(15.4, 11.4), 1.6, spot);
    canvas.drawCircle(const Offset(8.4, 16.6), 1.4, spot);
    canvas.drawCircle(const Offset(15.6, 16.6), 1.4, spot);
  }

  @override
  bool shouldRepaint(_LifeCyclePainter old) => old.level != level;
}

/// "Intermediate badge" pill with its life-cycle icon. Tap it for a small
/// message saying how many help seekers the badge takes.
class BadgeChip extends StatelessWidget {
  final BadgeLevel level;
  const BadgeChip(this.level, {super.key});
  @override
  Widget build(BuildContext context) {
    return _BadgeRequirementTip(
      level: level,
      child: Semantics(
        label: '${level.label} participation badge',
        excludeSemantics: true,
        child: Container(
          key: ValueKey('badge_${level.name}'),
          padding: const EdgeInsetsDirectional.fromSTEB(6, 3, 10, 3),
          decoration: BoxDecoration(
            color: _background(level),
            borderRadius: BorderRadius.circular(MaakRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BadgeIcon(level, size: 18),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${level.label} badge',
                  overflow: TextOverflow.ellipsis,
                  style: MaakText.caption.copyWith(
                    color: MaakColors.ink,
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

/// The signed-in volunteer's life-cycle stages and progress to the next one,
/// for their own profile. Shows nothing for other members.
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

  /// The one progress sentence, shown from the info button.
  static String progressText(BadgeProgress p) {
    final next = p.next, nextMin = p.nextMin;
    if (p.badge == null) {
      return 'No badge yet. Support your first help seeker to earn the Beginner badge.';
    }
    if (next == null || nextMin == null) {
      return 'You have supported ${_people(p.supported)}. This is the highest badge.';
    }
    final left = nextMin - p.supported;
    return 'You have supported ${_people(p.supported)}. ${left == 1 ? '1 more' : '$left more'} to earn the ${next.label} badge.';
  }

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
            child: SkeletonBlock(height: 120),
          ),
        );
      }
      final p = snapshot.data;
      if (p == null) return const SizedBox.shrink();
      return _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Flexible(
                  child: Text(
                    'My participation badge',
                    style: MaakText.itemTitle,
                  ),
                ),
                _InfoButton(progressText(p)),
              ],
            ),
            const SizedBox(height: MaakSpace.md),
            _LifeCycle(p),
          ],
        ),
      );
    },
  );

  Widget _card(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: MaakSpace.md),
    child: SoftCard(
      key: const ValueKey('my_badge_card'),
      padding: const EdgeInsets.all(MaakSpace.lg),
      child: child,
    ),
  );
}

/// Small "i" button. Tap (or long-press) shows [message]; screen readers
/// read it as the button's tooltip without opening anything.
class _InfoButton extends StatelessWidget {
  final String message;
  const _InfoButton(this.message);
  @override
  Widget build(BuildContext context) => Tooltip(
    key: const ValueKey('badge_progress_info'),
    message: message,
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 6),
    preferBelow: true,
    margin: const EdgeInsets.symmetric(horizontal: MaakSpace.xl),
    padding: const EdgeInsets.all(MaakSpace.md),
    decoration: BoxDecoration(
      color: MaakColors.ink,
      borderRadius: BorderRadius.circular(MaakRadius.card / 1.5),
    ),
    textStyle: MaakText.caption.copyWith(color: Colors.white, height: 1.4),
    child: Semantics(
      button: true,
      child: const SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: MaakColors.muted,
        ),
      ),
    ),
  );
}

/// Worm -> larva -> ladybug in a row. Reached stages are in colour, the
/// current one is ringed, and the link to the next stage fills with progress.
class _LifeCycle extends StatelessWidget {
  final BadgeProgress progress;
  const _LifeCycle(this.progress);

  static const _accent = Color(0xFFC24D5A);
  static const _stage = {
    BadgeLevel.beginner: 'Worm',
    BadgeLevel.intermediate: 'Larva',
    BadgeLevel.expert: 'Ladybug',
  };

  @override
  Widget build(BuildContext context) {
    final current = progress.badge;
    final reached = current?.index ?? -1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final level in BadgeLevel.values) ...[
          if (level.index > 0) Expanded(child: _link(level, reached)),
          _node(level, reached, level == current),
        ],
      ],
    );
  }

  /// The home card's orb colours (MaakGradients.orb), run along the line.
  static const _lineGradient = LinearGradient(
    begin: AlignmentDirectional.centerStart,
    end: AlignmentDirectional.centerEnd,
    colors: [MaakColors.orbPink, MaakColors.orbBlush, MaakColors.orbPeach],
    stops: [0, .48, 1],
  );

  /// The line leading into [level]'s stage: grey track, gradient fill.
  Widget _link(BadgeLevel level, int reached) {
    final nextMin = progress.nextMin;
    final double filled;
    if (level.index <= reached) {
      filled = 1;
    } else if (level == progress.next && nextMin != null && nextMin > 0) {
      filled = (progress.supported / nextMin).clamp(0, 1).toDouble();
    } else {
      filled = 0;
    }
    Widget line = Container(
      height: 8,
      color: MaakColors.fill,
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        key: ValueKey('link_${level.name}'),
        widthFactor: filled,
        heightFactor: 1,
        child: const DecoratedBox(
          decoration: BoxDecoration(gradient: _lineGradient),
        ),
      ),
    );
    if (level == progress.next && nextMin != null && nextMin > 0) {
      line = Semantics(
        container: true,
        label:
            'Progress to the ${level.label} badge: ${progress.supported} of $nextMin help seekers supported',
        excludeSemantics: true,
        child: line,
      );
    }
    return Padding(
      // Centred on the 56 px circles.
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MaakRadius.pill),
        child: line,
      ),
    );
  }

  Widget _node(BadgeLevel level, int reached, bool isCurrent) {
    final earned = level.index <= reached;
    final status = isCurrent
        ? 'your current badge'
        : (earned ? 'earned' : 'not earned yet');
    return _BadgeRequirementTip(
      level: level,
      stage: _stage[level],
      child: Semantics(
      container: true,
      label: '${_stage[level]}, ${level.label} badge, $status',
      excludeSemantics: true,
      // Fixed width so the links between stages always get room.
      child: SizedBox(
        width: 76,
        child: Column(
          key: ValueKey('stage_${level.name}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: earned ? _background(level) : MaakColors.fill,
                border: Border.all(
                  color: isCurrent ? _accent : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: BadgeIcon(level, size: 34, dimmed: !earned),
            ),
            const SizedBox(height: 6),
            Text(
              _stage[level]!,
              textAlign: TextAlign.center,
              style: MaakText.caption.copyWith(
                color: earned ? MaakColors.ink : MaakColors.muted,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Text(
              level.label,
              textAlign: TextAlign.center,
              style: MaakText.caption.copyWith(
                fontSize: 11,
                color: MaakColors.muted,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Tap (or long-press) a badge for a small message, styled like the progress
/// card's "i" button, saying how many help seekers the badge takes. The
/// numbers come from volunteer_badge_levels, which administrators can change;
/// screen readers read the message as the badge's tooltip.
class _BadgeRequirementTip extends StatelessWidget {
  final BadgeLevel level;

  /// Life-cycle stage name (Worm, Larva, Ladybug) when shown with the stages.
  final String? stage;
  final Widget child;
  const _BadgeRequirementTip({
    required this.level,
    required this.child,
    this.stage,
  });

  static String message(BadgeLevel level, int needed, {String? stage}) {
    final name = stage == null
        ? '${level.label} badge'
        : '$stage (${level.label} badge)';
    return needed == 1
        ? '$name: support your first help seeker to earn it.'
        : '$name: support $needed different help seekers to earn it.';
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Map<BadgeLevel, int>>(
        future: VolunteerStatsService.badgeThresholds(),
        builder: (context, snapshot) {
          final needed = (snapshot.data ??
              VolunteerStatsService.defaultBadgeThresholds)[level]!;
          return Tooltip(
            key: ValueKey('badge_requirement_${level.name}'),
            message: message(level, needed, stage: stage),
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 6),
            preferBelow: true,
            margin: const EdgeInsets.symmetric(horizontal: MaakSpace.xl),
            padding: const EdgeInsets.all(MaakSpace.md),
            decoration: BoxDecoration(
              color: MaakColors.ink,
              borderRadius: BorderRadius.circular(MaakRadius.card / 1.5),
            ),
            textStyle: MaakText.caption.copyWith(
              color: Colors.white,
              height: 1.4,
            ),
            child: child,
          );
        },
      );
}
