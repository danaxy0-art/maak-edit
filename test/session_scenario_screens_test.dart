// ADDED BY RAZAN: one full story, Rana (volunteer) and Layla (help seeker),
// rendered as the two people would see it at every step, from adding times to
// the day of the session. Images are written only with MAAK_SCREENSHOTS=1 and
// --update-goldens; a normal run just checks the texts on screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/redesign/sessions.dart';

import 'helpers/screen_harness.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

DateTime _day(int days, int hour, [int minute = 0]) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, hour, minute);
}

Map<String, dynamic> _s(
  String status,
  DateTime start, {
  required bool volunteer,
  String? display,
  int moved = 0,
  bool canceledByMe = false,
}) => {
  'id': 'b1',
  'slot_id': 'slot',
  'status': status,
  'display_status': display ?? status,
  'starts_at': _iso(start),
  'ends_at': _iso(start.add(const Duration(hours: 1))),
  'volunteer_id': 'vol',
  'seeker_id': 'seek',
  'is_volunteer': volunteer,
  'contact_name': volunteer ? 'Layla' : 'Rana',
  'reschedule_count': moved,
  'canceled_by_me': canceledByMe,
};

Future<void> _shot(WidgetTester tester, String name) async {
  if (Platform.environment['MAAK_SCREENSHOTS'] == '1') {
    await shot(tester, 'goldens/scenario/$name.png');
  }
}

Future<void> _view(
  WidgetTester tester,
  String file,
  bool volunteer,
  Map<String, dynamic> session,
  List<String> mustShow, {
  List<String> mustNotShow = const [],
}) async {
  fakeBackend = backendFrom({
    '/rpc/my_maak_sessions': [session],
  });
  await tester.runAsync(() => signIn(volunteer ? 'Rana' : 'Layla'));
  await pumpScreen(
    tester,
    SessionsPage(role: volunteer ? 'volunteer' : 'help_seeker'),
  );
  for (final t in mustShow) {
    expect(find.text(t), findsWidgets, reason: '$file should show "$t"');
  }
  for (final t in mustNotShow) {
    expect(find.text(t), findsNothing, reason: '$file should not show "$t"');
  }
  expect(tester.takeException(), isNull);
  await _shot(tester, file);
}

void main() {
  setUpAll(setUpScreenHarness);
  final later = _day(3, 18);
  // 90 minutes from now, but never past midnight, so it is always "Today".
  final now = DateTime.now();
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59);
  final soon = now.add(const Duration(minutes: 90)).isAfter(endOfDay)
      ? endOfDay
      : now.add(const Duration(minutes: 90));
  final started = DateTime.now().subtract(const Duration(minutes: 20));
  final over = DateTime.now().subtract(const Duration(hours: 3));

  testScreen('step 1: Rana adds her available times', (tester) async {
    fakeBackend = backendFrom({
      '/rpc/my_maak_time_slots': [
        for (final (i, d) in [_day(3, 18), _day(4, 17), _day(6, 20)].indexed)
          {
            'id': 's$i',
            'starts_at': _iso(d),
            'ends_at': _iso(d.add(const Duration(hours: 1))),
            'booking_id': null,
            'booking_status': null,
            'seeker_name': null,
          },
      ],
    });
    await tester.runAsync(() => signIn('Rana'));
    await pumpScreen(tester, const AvailabilityPage());
    expect(find.byTooltip('Remove time slot'), findsNWidgets(3));
    await _shot(tester, '01_volunteer_adds_times');
  });

  testScreen('step 2: Layla sees Rana\'s open times', (tester) async {
    fakeBackend = backendFrom({
      '/rpc/volunteer_available_slots': [
        for (final (i, d) in [_day(3, 18), _day(4, 17), _day(6, 20)].indexed)
          {
            'id': 's$i',
            'volunteer_id': 'vol',
            'starts_at': _iso(d),
            'ends_at': _iso(d.add(const Duration(hours: 1))),
          },
      ],
    });
    await tester.runAsync(() => signIn('Layla'));
    await pumpScreen(
      tester,
      const VolunteerSlotsPage(volunteerId: 'vol', volunteerName: 'Rana'),
    );
    expect(find.byIcon(Icons.schedule), findsNWidgets(3));
    await _shot(tester, '02_seeker_sees_times');
  });

  testScreen('step 3a: Layla asked, she sees "Awaiting response"', (t) async {
    await _view(
      t,
      '03a_seeker_pending',
      false,
      _s('pending', later, volunteer: false),
      ['Awaiting response', 'Reschedule', 'Cancel'],
      mustNotShow: ['Accept'],
    );
  });

  testScreen('step 3b: Rana sees the request with Accept / Decline', (t) async {
    await _view(
      t,
      '03b_volunteer_pending',
      true,
      _s('pending', later, volunteer: true),
      ['Awaiting response', 'Accept', 'Decline'],
      mustNotShow: ['Reschedule', 'Cancel'],
    );
  });

  testScreen('step 4a: after Accept, Layla sees "Confirmed"', (t) async {
    await _view(
      t,
      '04a_seeker_confirmed',
      false,
      _s('accepted', later, volunteer: false),
      ['Confirmed', 'Reschedule', 'Cancel'],
    );
  });

  testScreen('step 4b: after Accept, Rana sees "Confirmed"', (t) async {
    await _view(
      t,
      '04b_volunteer_confirmed',
      true,
      _s('accepted', later, volunteer: true),
      ['Confirmed', 'Reschedule', 'Cancel'],
      mustNotShow: ['Accept'],
    );
  });

  testScreen('step 5: Layla moved it, back to "Awaiting response" for Rana', (
    t,
  ) async {
    await _view(
      t,
      '05_volunteer_moved_pending',
      true,
      _s('pending', _day(4, 17), volunteer: true, moved: 1),
      ['Awaiting response', 'Accept'],
    );
  });

  testScreen('step 6a: the day comes, Layla sees "Today" and the countdown', (
    t,
  ) async {
    await _view(
      t,
      '06a_seeker_today',
      false,
      _s('accepted', soon, volunteer: false),
      ['Confirmed'],
    );
    expect(find.textContaining('Today ·'), findsOneWidget);
    expect(find.textContaining('Starts in'), findsOneWidget);
  });

  testScreen('step 6b: the day comes, Rana sees "Today" and the countdown', (
    t,
  ) async {
    await _view(
      t,
      '06b_volunteer_today',
      true,
      _s('accepted', soon, volunteer: true),
      ['Confirmed'],
    );
    expect(find.textContaining('Today ·'), findsOneWidget);
    expect(find.textContaining('Starts in'), findsOneWidget);
  });

  testScreen(
    'step 7a: during the session, Layla sees "Happening now", no buttons',
    (t) async {
      await _view(
        t,
        '07a_seeker_now',
        false,
        _s('accepted', started, volunteer: false, display: 'in_progress'),
        ['Happening now'],
        mustNotShow: ['Reschedule', 'Cancel', 'Accept'],
      );
    },
  );

  testScreen(
    'step 7b: during the session, Rana sees "Happening now", no buttons',
    (t) async {
      await _view(
        t,
        '07b_volunteer_now',
        true,
        _s('accepted', started, volunteer: true, display: 'in_progress'),
        ['Happening now'],
        mustNotShow: ['Reschedule', 'Cancel', 'Accept'],
      );
    },
  );

  testScreen('step 8a: after the session, Layla sees "Completed"', (t) async {
    await _view(
      t,
      '08a_seeker_done',
      false,
      _s('accepted', over, volunteer: false, display: 'completed'),
      ['Completed'],
      mustNotShow: ['Reschedule', 'Cancel'],
    );
  });

  testScreen('step 8b: after the session, Rana sees "Completed"', (t) async {
    await _view(
      t,
      '08b_volunteer_done',
      true,
      _s('accepted', over, volunteer: true, display: 'completed'),
      ['Completed'],
      mustNotShow: ['Reschedule', 'Cancel'],
    );
  });

  testScreen('side path: Rana canceled, Layla is told', (t) async {
    await _view(
      t,
      '09_seeker_canceled_by_volunteer',
      false,
      _s('canceled', later, volunteer: false),
      ['Canceled', 'Canceled by the other person.'],
      mustNotShow: ['Reschedule'],
    );
  });

  testScreen('side path: a request nobody answered before its time', (t) async {
    await _view(
      t,
      '10_volunteer_expired',
      true,
      _s('pending', over, volunteer: true, display: 'expired'),
      ['Expired'],
      mustNotShow: ['Accept', 'Decline'],
    );
  });
}
