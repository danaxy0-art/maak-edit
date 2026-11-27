// Sprint 4 US3/US4: widget checks for lib/frontend/redesign/badges.dart and
// where badges appear. Badge levels are derived and authorised in the
// database; see tests/database/volunteer_badges_test.mjs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:maak_app/backend/services/volunteer_stats_service.dart';
import 'package:maak_app/frontend/redesign/badges.dart';
import 'package:maak_app/frontend/redesign/profile.dart';
import 'package:maak_app/frontend/redesign/ratings.dart';
import 'package:maak_app/frontend/redesign/support.dart';

import 'helpers/screen_harness.dart';

List<http.Request> _calls(String rpc) =>
    sentRequests.where((r) => r.url.path.endsWith('/rpc/$rpc')).toList();

Map<String, Object?> _stats(String id, {String? badge, int count = 0}) => {
  'volunteer_id': id,
  'rating_count': count,
  'average_rating': null,
  'badge': badge,
};

Widget _progress(Future<BadgeProgress?> Function() load) => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(16),
    child: MyBadgeProgressCard(load: load),
  ),
);

/// The progress sentence behind the card's info button.
String? _info(WidgetTester tester) => tester
    .widget<Tooltip>(find.byKey(const ValueKey('badge_progress_info')))
    .message;

/// How much of the gradient line into a stage is filled, 0 to 1.
double? _link(WidgetTester tester, String stage) => tester
    .widget<FractionallySizedBox>(find.byKey(ValueKey('link_$stage')))
    .widthFactor;

/// Semantics label of one life-cycle stage.
Finder _stage(String label) => find.bySemanticsLabel(label);

void main() {
  setUpAll(setUpScreenHarness);
  setUp(VolunteerStatsService.resetCache);

  test('badge levels parse from the server and ignore unknown values', () {
    expect(BadgeLevel.parse('beginner'), BadgeLevel.beginner);
    expect(BadgeLevel.parse('intermediate'), BadgeLevel.intermediate);
    expect(BadgeLevel.parse('expert'), BadgeLevel.expert);
    expect(BadgeLevel.parse(null), isNull);
    expect(BadgeLevel.parse('master'), isNull);
    final s = VolunteerStats.fromJson({
      'volunteer_id': 'v1',
      'rating_count': 0,
      'badge': 'expert',
    });
    expect(s.badge, BadgeLevel.expert);
  });

  testWidgets('each badge has a text label, its own look and a spoken name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BadgeChip(BadgeLevel.beginner),
              BadgeChip(BadgeLevel.intermediate),
              BadgeChip(BadgeLevel.expert),
            ],
          ),
        ),
      ),
    );
    final colors = <Color?>{};
    for (final level in BadgeLevel.values) {
      expect(find.text('${level.label} badge'), findsOneWidget);
      expect(
        find.bySemanticsLabel('${level.label} participation badge'),
        findsOneWidget,
      );
      final box = tester.widget<Container>(
        find.byKey(ValueKey('badge_${level.name}')),
      );
      colors.add((box.decoration! as BoxDecoration).color);
    }
    expect(colors, hasLength(3), reason: 'visually distinct levels');
  });

  group('VolunteerStatsLine', () {
    testScreen('shows the badge next to the rating summary', (tester) async {
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': [_stats('v1', badge: 'intermediate')],
      });
      await pumpScreen(
        tester,
        const Scaffold(body: VolunteerStatsLine(volunteerId: 'v1')),
      );
      expect(find.text('Intermediate badge'), findsOneWidget);
      expect(find.text('No ratings yet'), findsOneWidget);
      expect(find.text(badgeMeaning), findsNothing, reason: 'cards stay short');
    });

    testScreen('no badge yet: rating summary only, no empty chip', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': [_stats('v1')],
      });
      await pumpScreen(
        tester,
        const Scaffold(
          body: VolunteerStatsLine(volunteerId: 'v1', explainBadge: true),
        ),
      );
      expect(find.byType(BadgeChip), findsNothing);
      expect(find.text(badgeMeaning), findsNothing);
      expect(find.text('No ratings yet'), findsOneWidget);
    });

    testScreen('cards and profile in one screen share one stats request', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': [
          _stats('v1', badge: 'expert', count: 1),
          _stats('v2', badge: 'beginner'),
        ],
      });
      await pumpScreen(
        tester,
        const Scaffold(
          body: Column(
            children: [
              VolunteerStatsLine(volunteerId: 'v1'),
              VolunteerStatsLine(volunteerId: 'v2'),
              VolunteerStatsLine(volunteerId: 'v1', explainBadge: true),
            ],
          ),
        ),
      );
      expect(_calls('maak_volunteer_stats'), hasLength(1));
      expect(find.text('Expert badge'), findsNWidgets(2));
      expect(find.text('Beginner badge'), findsOneWidget);
      expect(find.text('1 rating'), findsNWidgets(2));
    });
  });

  testScreen('volunteer profile shows the badge and what it means', (
    tester,
  ) async {
    fakeBackend = backendFrom({
      '/rpc/maak_volunteer_stats': [_stats('v1', badge: 'expert', count: 4)],
    });
    await pumpScreen(
      tester,
      const VolunteerDetailPage(
        volunteer: {
          'user_id': 'v1',
          'full_name': 'Sara Omar',
          'condition': 'Diabetes',
          'language': 'English',
        },
      ),
    );
    expect(find.text('Expert badge'), findsOneWidget);
    expect(find.text(badgeMeaning), findsOneWidget);
    expect(find.text('4 ratings'), findsOneWidget);
    expect(find.text('Approved volunteer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testScreen('volunteer directory shows badges on cards', (tester) async {
    await signIn('Dana');
    fakeBackend = backendFrom({
      '/rpc/browse_volunteers': [
        {
          'user_id': 'v1',
          'full_name': 'Sara Omar',
          'condition': 'Diabetes',
          'language': 'English',
        },
        {
          'user_id': 'v2',
          'full_name': 'Lina Saad',
          'condition': 'Asthma',
          'language': 'Arabic',
        },
      ],
      '/rpc/maak_volunteer_stats': [
        _stats('v1', badge: 'beginner'),
        _stats('v2'),
      ],
    });
    await pumpScreen(tester, const VolunteerDirectoryPage());
    expect(find.text('Beginner badge'), findsOneWidget);
    expect(find.byType(BadgeChip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('MyBadgeProgressCard', () {
    testScreen('loading, then the current badge and the next goal', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        _progress(
          () async => const BadgeProgress(
            supported: 3,
            badge: BadgeLevel.beginner,
            next: BadgeLevel.intermediate,
            nextMin: 5,
          ),
        ),
      );
      expect(find.byType(BadgeChip), findsNothing, reason: 'stages, no pill');
      for (final name in ['Worm', 'Larva', 'Ladybug']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(
        _stage('Worm, Beginner badge, your current badge'),
        findsOneWidget,
      );
      expect(
        _stage('Larva, Intermediate badge, not earned yet'),
        findsOneWidget,
      );
      expect(_stage('Ladybug, Expert badge, not earned yet'), findsOneWidget);
      const sentence =
          'You have supported 3 help seekers. 2 more to earn the Intermediate badge.';
      expect(_info(tester), sentence);
      expect(find.text(sentence), findsNothing, reason: 'behind the i button');
      expect(find.text(badgeMeaning), findsNothing);
      expect(
        find.textContaining('Each help seeker counts once'),
        findsNothing,
        reason: 'long explanation removed',
      );
      await tester.tap(find.byKey(const ValueKey('badge_progress_info')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(sentence), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(seconds: 1));
      expect(_link(tester, 'intermediate'), closeTo(0.6, 0.001));
      expect(_link(tester, 'expert'), 0, reason: 'not the next stage yet');
      expect(
        find.bySemanticsLabel(
          'Progress to the Intermediate badge: 3 of 5 help seekers supported',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows a loading placeholder while waiting', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _progress(() => Future.delayed(Duration(hours: 1)))),
      );
      expect(find.bySemanticsLabel('Loading your badge'), findsOneWidget);
      await tester.pump(const Duration(hours: 1));
    });

    testScreen('no badge yet explains how to earn Beginner', (tester) async {
      await pumpScreen(
        tester,
        _progress(
          () async => const BadgeProgress(
            supported: 0,
            next: BadgeLevel.beginner,
            nextMin: 1,
          ),
        ),
      );
      expect(find.byType(BadgeChip), findsNothing);
      expect(
        _info(tester),
        'No badge yet. Support your first help seeker to earn the Beginner badge.',
      );
      expect(_stage('Worm, Beginner badge, not earned yet'), findsOneWidget);
    });

    testScreen('expert: highest badge, no progress bar', (tester) async {
      await pumpScreen(
        tester,
        _progress(
          () async =>
              const BadgeProgress(supported: 21, badge: BadgeLevel.expert),
        ),
      );
      expect(_stage('Worm, Beginner badge, earned'), findsOneWidget);
      expect(_stage('Larva, Intermediate badge, earned'), findsOneWidget);
      expect(
        _stage('Ladybug, Expert badge, your current badge'),
        findsOneWidget,
      );
      expect(
        _info(tester),
        'You have supported 21 help seekers. This is the highest badge.',
      );
      expect(_link(tester, 'intermediate'), 1);
      expect(_link(tester, 'expert'), 1);
      expect(find.bySemanticsLabel(RegExp('^Progress to')), findsNothing);
    });

    testScreen('not a volunteer (server returns null): nothing shown', (
      tester,
    ) async {
      await pumpScreen(tester, _progress(() async => null));
      expect(find.byKey(const ValueKey('my_badge_card')), findsNothing);
    });

    testScreen('a failed load offers Retry', (tester) async {
      var calls = 0;
      await pumpScreen(
        tester,
        _progress(() async {
          if (calls++ == 0) throw http.ClientException('offline');
          return const BadgeProgress(
            supported: 1,
            badge: BadgeLevel.beginner,
            next: BadgeLevel.intermediate,
            nextMin: 5,
          );
        }),
      );
      expect(find.textContaining('Could not load your badge.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(
        _stage('Worm, Beginner badge, your current badge'),
        findsOneWidget,
      );
    });
  });

  testScreen('a volunteer\'s own profile shows their badge progress', (
    tester,
  ) async {
    await signIn('Sara');
    fakeBackend = (request) {
      final path = request.url.path;
      final single =
          request.headers['accept']?.contains('vnd.pgrst.object') == true;
      Object? body;
      if (path.endsWith('/profiles')) {
        final row = {
          'full_name': 'Sara',
          'username': 'sara',
          'role': 'volunteer',
        };
        body = single ? row : [row];
      } else if (path.endsWith('/volunteer_profiles')) {
        final row = {
          'user_id': '00000000-0000-0000-0000-000000000001',
          'condition_experience': 'Diabetes',
          'preferred_language': 'English',
          'experience_description': 'Story',
          'status': 'approved',
        };
        body = single ? row : [row];
      } else if (path.endsWith('/rpc/my_maak_badge_progress')) {
        body = {
          'supported': 6,
          'badge': 'intermediate',
          'next_badge': 'expert',
          'next_min': 15,
        };
      }
      return body == null ? null : Future.value(jsonResponse(request, body));
    };
    await pumpScreen(tester, const ProfilePage(role: 'volunteer'));
    expect(find.text('My participation badge'), findsOneWidget);
    expect(
      _stage('Larva, Intermediate badge, your current badge'),
      findsOneWidget,
    );
    expect(
      _info(tester),
      'You have supported 6 help seekers. 9 more to earn the Expert badge.',
    );
  });

  testScreen('a help seeker\'s own profile has no badge card', (tester) async {
    await signIn('Dana');
    fakeBackend = (request) {
      final path = request.url.path;
      final single =
          request.headers['accept']?.contains('vnd.pgrst.object') == true;
      if (path.endsWith('/profiles')) {
        final row = {
          'full_name': 'Dana',
          'username': 'dana',
          'role': 'help_seeker',
        };
        return Future.value(jsonResponse(request, single ? row : [row]));
      }
      return null;
    };
    await pumpScreen(tester, const ProfilePage(role: 'help_seeker'));
    expect(find.text('Dana'), findsWidgets);
    expect(find.text('My participation badge'), findsNothing);
    expect(_calls('my_maak_badge_progress'), isEmpty);
  });
}
