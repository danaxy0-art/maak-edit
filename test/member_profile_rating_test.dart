// Sprint 4 US2: a volunteer's rating on the profile opened from a chat
// (MemberProfilePage, opened by tapping the chat header). MOCKED backend.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/services/volunteer_stats_service.dart';
import 'package:maak_app/frontend/redesign/member_profile.dart';

import 'helpers/screen_harness.dart';

const _volunteer = '00000000-0000-0000-0000-0000000000v1';

Map<String, Object?> _profile({
  String role = 'volunteer',
  bool approved = true,
}) => {
  'user_id': _volunteer,
  'full_name': 'Noura',
  'role': role,
  'member_since': '2026-03-01T00:00:00Z',
  'is_self': false,
  'connected': true,
  if (role == 'volunteer') 'approved': approved,
};

Map<String, Object?> _stats({int count = 4, double? average = 4.5}) => {
  'volunteer_id': _volunteer,
  'rating_count': count,
  'average_rating': average,
  'badge': 'beginner',
};

Future<void> _open(WidgetTester tester, Map<String, Object> routes) async {
  await signIn('Sara');
  fakeBackend = backendFrom({
    '/profiles': [
      {'role': 'help_seeker'},
    ],
    ...routes,
  });
  await pumpScreen(
    tester,
    const MemberProfilePage(userId: _volunteer, name: 'Noura'),
  );
}

void main() {
  setUpAll(setUpScreenHarness);
  setUp(VolunteerStatsService.resetCache);

  testScreen('a help seeker sees the volunteer\'s average and rating count', (
    tester,
  ) async {
    await _open(tester, {
      '/rpc/get_maak_member_profile': _profile(),
      '/rpc/maak_volunteer_stats': [_stats()],
      '/volunteer_badge_levels': [],
    });
    expect(
      find.byKey(const ValueKey('volunteer_rating_summary')),
      findsOneWidget,
    );
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('(4 ratings)'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Rated 4.5 out of 5 from 4 ratings')),
      findsOneWidget,
    );
  });

  testScreen('fewer ratings than needed for an average: the count only', (
    tester,
  ) async {
    await _open(tester, {
      '/rpc/get_maak_member_profile': _profile(),
      '/rpc/maak_volunteer_stats': [_stats(count: 2, average: null)],
      '/volunteer_badge_levels': [],
    });
    expect(find.text('2 ratings'), findsOneWidget);
  });

  testScreen('no ratings yet says so', (tester) async {
    await _open(tester, {
      '/rpc/get_maak_member_profile': _profile(),
      '/rpc/maak_volunteer_stats': [_stats(count: 0, average: null)],
      '/volunteer_badge_levels': [],
    });
    expect(find.text('No ratings yet'), findsOneWidget);
  });

  testScreen('a help seeker\'s profile shows no rating', (tester) async {
    await _open(tester, {
      '/rpc/get_maak_member_profile': _profile(role: 'help_seeker'),
      '/rpc/maak_volunteer_stats': [_stats()],
    });
    expect(
      find.byKey(const ValueKey('volunteer_rating_summary')),
      findsNothing,
    );
  });
}
