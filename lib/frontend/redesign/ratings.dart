import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/services/volunteer_stats_service.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import 'badges.dart';
import 'feedback.dart';

// Volunteer ratings UI (Sprint 4 US1, US2) and the shared stats line that also
// shows the participation badge (US4). Rules live in the database
// (20261126100000_volunteer_ratings.sql, 20261126110000_volunteer_badges.sql);
// these widgets only show its answers.

/// Star colour: Ma'ak coral, darkened to keep 3:1 contrast on white.
const _starColor = Color(0xFFC24D5A);

String _ratingsText(int count) => count == 1 ? '1 rating' : '$count ratings';

/// Read-only stars for [value] (0-5, halves rounded to the nearest half).
class StarsDisplay extends StatelessWidget {
  final double value;
  final double size;
  const StarsDisplay(this.value, {super.key, this.size = 16});
  @override
  Widget build(BuildContext context) {
    final halves = (value * 2).round();
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              halves >= i * 2
                  ? Icons.star_rounded
                  : halves == i * 2 - 1
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded,
              size: size,
              color: _starColor,
            ),
        ],
      ),
    );
  }
}

/// 1-5 star picker. Each star is a 48 pt button that reads as "3 stars".
class StarRatingInput extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  const StarRatingInput({super.key, required this.value, this.onChanged});

  static const labels = ['Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        Semantics(
          button: true,
          selected: value == i,
          enabled: onChanged != null,
          label: '${i == 1 ? '1 star' : '$i stars'}, ${labels[i - 1]}',
          excludeSemantics: true,
          child: InkResponse(
            key: ValueKey('rating_star_$i'),
            onTap: onChanged == null ? null : () => onChanged!(i),
            radius: 24,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 34,
                color: onChanged == null && i > value
                    ? MaakColors.border
                    : _starColor,
              ),
            ),
          ),
        ),
    ],
  );
}

/// A volunteer's public stats: the participation badge, if earned, and the
/// rating summary ("4.6 ★★★★★ (12 ratings)", "2 ratings" or "No ratings yet").
/// Shows nothing until loaded, or when there is no summary for this member.
class VolunteerStatsLine extends StatefulWidget {
  final String? volunteerId;

  /// Space above the line, only when something is shown.
  final double top;
  final bool center;

  /// Adds the note that badges reflect participation, not medical expertise.
  final bool explainBadge;
  const VolunteerStatsLine({
    super.key,
    required this.volunteerId,
    this.top = MaakSpace.sm,
    this.center = false,
    this.explainBadge = false,
  });
  @override
  State<VolunteerStatsLine> createState() => _VolunteerStatsLineState();
}

class _VolunteerStatsLineState extends State<VolunteerStatsLine> {
  Future<VolunteerStats?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VolunteerStatsLine old) {
    super.didUpdateWidget(old);
    if (old.volunteerId != widget.volunteerId) _load();
  }

  void _load() {
    final id = widget.volunteerId;
    _future = id == null || id.isEmpty ? null : VolunteerStatsService.stats(id);
  }

  Widget _rating(VolunteerStats stats) {
    final average = stats.averageRating;
    final String label;
    final List<Widget> parts;
    if (stats.ratingCount == 0) {
      label = 'No ratings yet';
      parts = [
        const Icon(Icons.star_outline_rounded, size: 16, color: _starColor),
        const SizedBox(width: 4),
        Text('No ratings yet', style: MaakText.caption),
      ];
    } else if (average == null) {
      // Too few ratings for an average that keeps each score private.
      label = _ratingsText(stats.ratingCount);
      parts = [
        const Icon(Icons.star_rounded, size: 16, color: _starColor),
        const SizedBox(width: 4),
        Text(label, style: MaakText.caption),
      ];
    } else {
      final value = average.toStringAsFixed(1);
      label = 'Rated $value out of 5 from ${_ratingsText(stats.ratingCount)}';
      parts = [
        Text(
          value,
          style: MaakText.caption.copyWith(
            color: MaakColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        StarsDisplay(average, size: 15),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '(${_ratingsText(stats.ratingCount)})',
            style: MaakText.caption,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ];
    }
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('volunteer_rating_summary'),
        mainAxisSize: MainAxisSize.min,
        children: parts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VolunteerStats?>(
    future: _future,
    builder: (context, snapshot) {
      final stats = snapshot.data;
      if (stats == null) return const SizedBox.shrink();
      final badge = stats.badge;
      return Padding(
        padding: EdgeInsets.only(top: widget.top),
        child: Column(
          crossAxisAlignment: widget.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: widget.center
                  ? WrapAlignment.center
                  : WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: MaakSpace.sm,
              runSpacing: MaakSpace.xs,
              children: [if (badge != null) BadgeChip(badge), _rating(stats)],
            ),
            if (widget.explainBadge && badge != null) ...[
              const SizedBox(height: MaakSpace.xs),
              Text(
                badgeMeaning,
                textAlign: widget.center ? TextAlign.center : TextAlign.start,
                style: MaakText.caption.copyWith(fontSize: 12),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Rating prompt for an ended conversation. The server decides whether the
/// signed-in member may rate or correct; for anyone else this shows nothing.
class RateVolunteerCard extends StatefulWidget {
  /// The device clock the correction deadline is compared with. Tests replace
  /// it so they never depend on real time passing.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  final String requestId;
  final String volunteerName;
  const RateVolunteerCard({
    super.key,
    required this.requestId,
    required this.volunteerName,
  });
  @override
  State<RateVolunteerCard> createState() => _RateVolunteerCardState();
}

/// What a member sees for each known refusal (see [RatingError]).
const ratingErrorText = {
  RatingError.alreadyRated: 'You have already rated this conversation.',
  RatingError.notAllowed: 'This conversation can no longer be rated.',
  RatingError.correctionNotAllowed: 'This rating can no longer be changed.',
  RatingError.notFound: 'This rating can no longer be changed.',
  RatingError.unchanged:
      'Choose a different number of stars to change your rating.',
  RatingError.invalidStars: 'Choose from 1 to 5 stars.',
};

/// "24 hours", "1 hour", "30 minutes": the server's correction window.
String correctionWindowText(Duration window) {
  if (window.inMinutes % 60 == 0) {
    final h = window.inHours;
    return h == 1 ? '1 hour' : '$h hours';
  }
  final m = window.inMinutes;
  return m == 1 ? '1 minute' : '$m minutes';
}

/// "today at 3:45 PM", "tomorrow at 15:45", "Nov 30, 2026 at 3:45 PM", in the
/// device's time zone and the app locale's date and time formats.
String correctionDeadlineText(BuildContext context, DateTime until) {
  final local = until.toLocal();
  final loc = MaterialLocalizations.of(context);
  final time = loc.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  final now = RateVolunteerCard.clock();
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => loc.formatMediumDate(local),
  };
  return '$day at $time';
}

class _RateVolunteerCardState extends State<RateVolunteerCard> {
  RatingStatus? _status;
  Object? _loadError;
  int _stars = 0;
  bool _busy = false, _correcting = false;
  String? _submitError;

  // Fires once, at the server's correction deadline, so the offer never
  // stays on screen after it has expired. Not a poll.
  Timer? _deadline;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deadline?.cancel();
    super.dispose();
  }

  void _show(RatingStatus status) {
    _deadline?.cancel();
    _deadline = null;
    final until = status.correctUntil;
    if (status.canCorrectAt(RateVolunteerCard.clock()) && until != null) {
      _deadline = Timer(until.difference(RateVolunteerCard.clock()), () {
        if (mounted) setState(() => _correcting = false);
      });
    }
    _status = status;
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final status = await VolunteerStatsService.ratingFor(widget.requestId);
      if (mounted) setState(() => _show(status));
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _submit() async {
    if (_busy || _stars == 0) return;
    final correcting = _correcting;
    setState(() {
      _busy = true;
      _submitError = null;
    });
    try {
      final status = correcting
          ? await VolunteerStatsService.correct(widget.requestId, _stars)
          : await VolunteerStatsService.rate(widget.requestId, _stars);
      if (!mounted) return;
      setState(() {
        _show(status);
        _correcting = false;
      });
      showSuccess(
        context,
        correcting
            ? 'Your rating was changed.'
            : 'Thank you. Your rating was submitted.',
      );
    } catch (e) {
      if (!mounted) return;
      final known = RatingError.of(e);
      setState(
        () => _submitError = known == null
            ? friendlyError(e)
            : ratingErrorText[known],
      );
      // The server knows better (rated on another device, window passed).
      if (known != null && known.staleState) {
        setState(() => _correcting = false);
        unawaited(_load());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCorrection(int current) => setState(() {
    _correcting = true;
    _stars = current;
    _submitError = null;
  });

  Widget _frame(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(
      MaakSpace.lg,
      MaakSpace.sm,
      MaakSpace.lg,
      0,
    ),
    child: Semantics(
      container: true,
      liveRegion: true,
      child: SoftCard(
        key: const ValueKey('rate_volunteer_card'),
        padding: const EdgeInsets.all(MaakSpace.md),
        child: child,
      ),
    ),
  );

  Widget _error() => Padding(
    padding: const EdgeInsets.only(top: MaakSpace.xs),
    child: Text(
      _submitError!,
      key: const ValueKey('rating_error'),
      style: MaakText.caption.copyWith(color: MaakColors.error),
    ),
  );

  // The star picker, for a first rating or the one correction.
  Widget _input({
    required String title,
    required String note,
    required String action,
    VoidCallback? cancel,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: MaakText.itemTitle),
      const SizedBox(height: 2),
      Text(note, style: MaakText.caption),
      const SizedBox(height: MaakSpace.xs),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: MaakSpace.sm,
        runSpacing: MaakSpace.xs,
        children: [
          StarRatingInput(
            value: _stars,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _stars = v;
                    _submitError = null;
                  }),
          ),
          PillButton(
            action,
            compact: true,
            busy: _busy,
            onPressed: _stars == 0 || _busy ? null : _submit,
          ),
          if (cancel != null)
            TextButton(
              onPressed: _busy ? null : cancel,
              child: const Text('Cancel'),
            ),
        ],
      ),
      if (_stars > 0)
        Text(StarRatingInput.labels[_stars - 1], style: MaakText.caption),
      if (_submitError != null) _error(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return _frame(
        Row(
          children: [
            Expanded(
              child: Text(
                'Could not load the rating for this conversation.',
                style: MaakText.caption,
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final name = widget.volunteerName;
    switch (status.state) {
      case RatingState.hidden:
      case RatingState.notEnded:
      case RatingState.restricted:
        return const SizedBox.shrink();
      case RatingState.noSupport:
        return _frame(
          Row(
            children: [
              const Icon(Icons.star_outline_rounded, color: MaakColors.muted),
              const SizedBox(width: MaakSpace.sm),
              Expanded(
                child: Text(
                  'Ratings are available once the volunteer has replied in the conversation.',
                  style: MaakText.caption,
                ),
              ),
            ],
          ),
        );
      case RatingState.rated:
        final stars = status.stars ?? 0;
        final until = status.correctUntil;
        final canCorrect =
            status.canCorrectAt(RateVolunteerCard.clock()) && until != null;
        if (_correcting && canCorrect) {
          return _frame(
            _input(
              title: 'Change your rating of $name',
              note:
                  'Save by ${correctionDeadlineText(context, until)}. You can change a rating only once; after that it is final.',
              action: 'Save change',
              cancel: () => setState(() {
                _correcting = false;
                _submitError = null;
              }),
            ),
          );
        }
        return _frame(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label:
                    'You rated $name $stars out of 5. Thank you for your feedback.',
                excludeSemantics: true,
                child: Row(
                  children: [
                    StarsDisplay(stars.toDouble(), size: 18),
                    const SizedBox(width: MaakSpace.sm),
                    Expanded(
                      child: Text(
                        'You rated $name $stars of 5. Thank you for your feedback.',
                        style: MaakText.caption.copyWith(color: MaakColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
              if (canCorrect) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => _startCorrection(stars),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Change rating (once)'),
                  ),
                ),
                Text(
                  'You can change it once, until ${correctionDeadlineText(context, until)}.',
                  key: const ValueKey('correction_deadline'),
                  style: MaakText.caption,
                ),
              ],
              if (_submitError != null) _error(),
            ],
          ),
        );
      case RatingState.eligible:
        final window = status.correctionWindow;
        return _frame(
          _input(
            title: 'How was your support from $name?',
            // Worded from the server's window; nothing is promised without it.
            note: [
              'Only the overall average is shown on profiles, never who rated.',
              if (window != null)
                'You can change your rating once within ${correctionWindowText(window)}.',
            ].join(' '),
            action: 'Submit rating',
          ),
        );
    }
  }
}
