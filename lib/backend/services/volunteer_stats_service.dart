import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'supabase_service.dart';

// Volunteer ratings and achievement badges (Sprint 4 US1-US4).
// Backed by supabase/migrations/20261126100000_volunteer_ratings.sql and
// 20261126110000_volunteer_badges.sql, which enforce every rule; this class
// only calls their RPCs.

/// Participation badge levels, lowest first. They reflect how many distinct
/// help seekers a volunteer has supported on Ma'ak, not medical expertise.
enum BadgeLevel {
  beginner('Beginner'),
  intermediate('Intermediate'),
  expert('Expert');

  final String label;
  const BadgeLevel(this.label);

  static BadgeLevel? parse(Object? value) => switch (value) {
    'beginner' => BadgeLevel.beginner,
    'intermediate' => BadgeLevel.intermediate,
    'expert' => BadgeLevel.expert,
    _ => null,
  };
}

/// Public summary of one volunteer. [averageRating] is null until the volunteer
/// has enough ratings for the average not to reveal any single score.
@immutable
class VolunteerStats {
  final String volunteerId;
  final int ratingCount;
  final double? averageRating;
  final BadgeLevel? badge;
  const VolunteerStats({
    required this.volunteerId,
    required this.ratingCount,
    this.averageRating,
    this.badge,
  });

  factory VolunteerStats.fromJson(Map<String, dynamic> json) => VolunteerStats(
    volunteerId: json['volunteer_id'] as String,
    ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    averageRating: (json['average_rating'] as num?)?.toDouble(),
    badge: BadgeLevel.parse(json['badge']),
  );
}

/// The signed-in volunteer's own badge progress.
@immutable
class BadgeProgress {
  /// Distinct help seekers given completed support.
  final int supported;
  final BadgeLevel? badge;
  final BadgeLevel? next;
  final int? nextMin;

  /// Help seekers needed for the current badge (0 without one): progress to
  /// the next badge is counted from here, not from zero.
  final int currentMin;
  const BadgeProgress({
    required this.supported,
    this.badge,
    this.next,
    this.nextMin,
    this.currentMin = 0,
  });

  /// Share of the way from the current badge to the next one, 0 to 1; null
  /// at the highest badge.
  double? get towardNext {
    final target = nextMin;
    if (next == null || target == null || target <= currentMin) return null;
    return ((supported - currentMin) / (target - currentMin))
        .clamp(0, 1)
        .toDouble();
  }

  static BadgeProgress? fromJson(Object? json, {Map<String, int>? levels}) =>
      json is Map
      ? BadgeProgress(
          supported: (json['supported'] as num?)?.toInt() ?? 0,
          badge: BadgeLevel.parse(json['badge']),
          next: BadgeLevel.parse(json['next_badge']),
          nextMin: (json['next_min'] as num?)?.toInt(),
          currentMin: levels?['${json['badge']}'] ?? 0,
        )
      : null;
}

/// The signed-in help seeker's rating state for one conversation.
enum RatingState {
  /// Can rate now.
  eligible,

  /// Already rated; [RatingStatus.stars] holds the rating.
  rated,

  /// The conversation is still open.
  notEnded,

  /// The volunteer never replied, so there was no support to rate.
  noSupport,

  /// Ended by an administrator.
  restricted,

  /// Not the help seeker, or the conversation/volunteer is unavailable.
  hidden,
}

@immutable
class RatingStatus {
  final RatingState state;
  final int? stars;
  final String? volunteerId;

  /// The one allowed correction is still available (until [correctUntil],
  /// the server's deadline, converted to local time).
  final bool canCorrect;
  final DateTime? correctUntil;

  /// How long after submitting a correction is allowed (server setting).
  final Duration? correctionWindow;
  const RatingStatus(
    this.state, {
    this.stars,
    this.volunteerId,
    this.canCorrect = false,
    this.correctUntil,
    this.correctionWindow,
  });

  /// The correction is offered and its deadline has not passed on this device.
  bool canCorrectAt(DateTime now) {
    final until = correctUntil;
    return canCorrect && until != null && now.isBefore(until);
  }

  static const hidden = RatingStatus(RatingState.hidden);

  /// Anything unexpected is treated as "nothing to show".
  factory RatingStatus.fromJson(Object? json) {
    if (json is! Map) return hidden;
    final state = switch (json['state']) {
      'eligible' => RatingState.eligible,
      'rated' => RatingState.rated,
      'not_ended' => RatingState.notEnded,
      'no_support' => RatingState.noSupport,
      'restricted' => RatingState.restricted,
      _ => RatingState.hidden,
    };
    return RatingStatus(
      state,
      stars: (json['stars'] as num?)?.toInt(),
      volunteerId: json['volunteer_id'] as String?,
      canCorrect: json['can_correct'] == true,
      correctUntil: DateTime.tryParse(
        '${json['correct_until'] ?? ''}',
      )?.toLocal(),
      correctionWindow: switch (json['correction_window_seconds']) {
        final num s when s > 0 => Duration(seconds: s.toInt()),
        _ => null,
      },
    );
  }
}

/// Known refusals from the rating RPCs. The database raises these exact
/// identifiers; this is the one place that recognises them.
enum RatingError {
  alreadyRated('already_rated'),
  notAllowed('rating_not_allowed'),
  correctionNotAllowed('correction_not_allowed'),
  notFound('rating_not_found'),
  unchanged('rating_unchanged'),
  invalidStars('invalid_rating');

  final String code;
  const RatingError(this.code);

  /// The rating was refused because the server state changed (rated on
  /// another device, window passed, chat moderated): reload it.
  bool get staleState => this != unchanged && this != invalidStars;

  /// The known error behind [error], or null for anything else.
  static RatingError? of(Object error) {
    if (error is! PostgrestException) return null;
    final message = error.message.trim();
    for (final e in values) {
      if (message == e.code) return e;
    }
    return null;
  }
}

class VolunteerStatsService {
  VolunteerStatsService._();

  /// How long a loaded summary is reused before it is fetched again. The
  /// server always applies current approval and block status; this only
  /// bounds how stale a card already on screen can be.
  static const cacheFor = Duration(minutes: 5);

  /// The server accepts at most this many volunteers per call.
  static const _batchLimit = 100;

  static final _cache = <String, ({DateTime at, Future<VolunteerStats?> f})>{};
  static final _waiting = <String, Completer<VolunteerStats?>>{};
  static bool _flushScheduled = false;

  // The signed-in account the cache belongs to, and a generation that changes
  // with it. A request records the generation it was sent under; a response
  // that arrives after the account changed never touches the cache.
  static String? _cacheOwner;
  static int _generation = 0;

  /// Rating state of the conversation [requestId] for the signed-in member.
  static Future<RatingStatus> ratingFor(String requestId) async =>
      RatingStatus.fromJson(
        await SupabaseService.client.rpc(
          'my_maak_rating',
          params: {'p_request_id': requestId},
        ),
      );

  /// Submits a 1-5 star rating. Throws the server error when not allowed.
  static Future<RatingStatus> rate(String requestId, int stars) =>
      _changeRating('rate_maak_volunteer', requestId, stars);

  /// The one allowed correction of a submitted rating.
  static Future<RatingStatus> correct(String requestId, int stars) =>
      _changeRating('correct_maak_rating', requestId, stars);

  static Future<RatingStatus> _changeRating(
    String rpc,
    String requestId,
    int stars,
  ) async {
    final status = RatingStatus.fromJson(
      await SupabaseService.client.rpc(
        rpc,
        params: {'p_request_id': requestId, 'p_stars': stars},
      ),
    );
    final volunteerId = status.volunteerId;
    if (volunteerId != null) invalidate(volunteerId);
    return status;
  }

  /// The signed-in volunteer's badge progress; null for other members.
  /// Thresholds used when volunteer_badge_levels can't be read (the
  /// provisionally approved values in 20261126110000_volunteer_badges.sql).
  static const defaultBadgeThresholds = {
    BadgeLevel.beginner: 1,
    BadgeLevel.intermediate: 5,
    BadgeLevel.expert: 15,
  };

  static Future<Map<BadgeLevel, int>>? _thresholds;

  /// Help seekers needed for each badge, from volunteer_badge_levels (which
  /// administrators can change). Read once per app run.
  static Future<Map<BadgeLevel, int>> badgeThresholds() =>
      _thresholds ??= _loadThresholds();

  static Future<Map<BadgeLevel, int>> _loadThresholds() async {
    try {
      final rows = await SupabaseService.client
          .from('volunteer_badge_levels')
          .select('level,min_supported')
          .order('rank');
      final result = <BadgeLevel, int>{};
      for (final row in rows) {
        final level = BadgeLevel.parse(row['level']);
        final min = (row['min_supported'] as num?)?.toInt();
        if (level != null && min != null) result[level] = min;
      }
      if (result.length == BadgeLevel.values.length) return result;
    } catch (error) {
      debugPrint('Badge thresholds unavailable: ${error.runtimeType}');
    }
    // Kept for this app run, so badges on screen don't each retry.
    return defaultBadgeThresholds;
  }

  static Future<BadgeProgress?> myBadgeProgress() async {
    final json = await SupabaseService.client.rpc('my_maak_badge_progress');
    // The same thresholds the badge tips use give the current badge's start,
    // so the progress line is measured between this badge and the next.
    final thresholds = await badgeThresholds();
    return BadgeProgress.fromJson(
      json,
      levels: {for (final e in thresholds.entries) e.key.name: e.value},
    );
  }

  /// Summary for one volunteer, or null when none is available (not an
  /// approved, active volunteer, or the summary could not be loaded).
  /// Calls made in the same frame share one request.
  static Future<VolunteerStats?> stats(String volunteerId) {
    _syncOwner();
    final cached = _cache[volunteerId];
    if (cached != null && DateTime.now().difference(cached.at) < cacheFor) {
      return cached.f;
    }
    final completer = _waiting.putIfAbsent(volunteerId, Completer.new);
    _cache[volunteerId] = (at: DateTime.now(), f: completer.future);
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  /// Forgets a volunteer's summary so the next view loads it again.
  static void invalidate(String volunteerId) => _cache.remove(volunteerId);

  @visibleForTesting
  static void resetCache() {
    _cache.clear();
    _thresholds = null;
    _waiting.clear();
    _flushScheduled = false;
    _cacheOwner = null;
    _generation++;
  }

  // Another account signed in (or out): start a new generation with an empty
  // cache. Requests not yet sent for the old account are answered with null.
  static void _syncOwner() {
    final owner = SupabaseService.currentUser?.id;
    if (owner == _cacheOwner) return;
    _cacheOwner = owner;
    _generation++;
    _cache.clear();
    for (final c in _waiting.values) {
      c.complete(null);
    }
    _waiting.clear();
  }

  static Future<void> _flush() async {
    _flushScheduled = false;
    final generation = _generation;
    final batch = Map.of(_waiting);
    _waiting.clear();
    final ids = batch.keys.toList();
    for (var i = 0; i < ids.length; i += _batchLimit) {
      final chunk = ids.sublist(
        i,
        i + _batchLimit > ids.length ? ids.length : i + _batchLimit,
      );
      final found = <String, VolunteerStats>{};
      try {
        final rows = await SupabaseService.client.rpc(
          'maak_volunteer_stats',
          params: {'p_volunteer_ids': chunk},
        );
        if (rows is List) {
          for (final row in rows) {
            if (row is! Map) continue;
            final stats = VolunteerStats.fromJson(
              Map<String, dynamic>.from(row),
            );
            found[stats.volunteerId] = stats;
          }
        }
      } catch (_) {
        // The summary is secondary information: cards simply show without it,
        // and the next view tries again. Only this request's own entries are
        // dropped, and never after the account changed.
        if (generation == _generation) {
          for (final id in chunk) {
            if (identical(_cache[id]?.f, batch[id]!.future)) _cache.remove(id);
          }
        }
      }
      for (final id in chunk) {
        batch[id]!.complete(found[id]);
      }
    }
  }
}
