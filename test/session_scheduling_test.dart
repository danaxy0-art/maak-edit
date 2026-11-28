// ADDED BY RAZAN: widget checks (and optional screenshots) for the session
// scheduling screens in lib/frontend/redesign/sessions.dart.
// Screenshots are written only when MAAK_SCREENSHOTS=1 and the test is run
// with --update-goldens, so normal runs need no image files.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/redesign/sessions.dart';

import 'helpers/screen_harness.dart';

String _at(int days, int hour, [int minute = 0]) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day + days,
    hour,
    minute,
  ).toUtc().toIso8601String();
}

String _end(int days, int hour, int minutes) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day + days,
    hour,
    minutes,
  ).toUtc().toIso8601String();
}

Map<String, dynamic> _session(
  String id,
  String status,
  String name,
  int days,
  int hour, {
  bool volunteer = false,
  int moved = 0,
  bool canceledByMe = false,
}) => {
  'id': id,
  'slot_id': 'slot-$id',
  'status': status,
  'display_status': status,
  'starts_at': _at(days, hour),
  'ends_at': _end(days, hour, 60),
  'volunteer_id': 'vol-1',
  'seeker_id': 'seek-1',
  'is_volunteer': volunteer,
  'contact_name': name,
  'reschedule_count': moved,
  'canceled_by_me': canceledByMe,
};

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder, warnIfMissed: false);
  await settle(tester);
}

Map<String, dynamic>? _lastBody(String rpc) {
  final hits = sentRequests.where((r) => r.url.path.endsWith('/rpc/$rpc'));
  if (hits.isEmpty) return null;
  return jsonDecode(hits.last.body) as Map<String, dynamic>;
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (Platform.environment['MAAK_SCREENSHOTS'] == '1') {
    await shot(tester, 'goldens/sessions/$name.png');
  }
}

void main() {
  setUpAll(setUpScreenHarness);

  final volunteerSessions = [
    _session('s1', 'pending', 'Layla', 3, 18, volunteer: true),
    _session('s2', 'accepted', 'Noura', 5, 20, volunteer: true, moved: 1),
    _session('s3', 'rejected', 'Sara', 1, 17, volunteer: true),
  ];
  final seekerSessions = [
    _session('s4', 'pending', 'Dana', 3, 18),
    _session('s5', 'accepted', 'Huda', 6, 19),
    _session('s6', 'canceled', 'Dana', 2, 16),
  ];

  testScreen('volunteer: my available times lists slots and who holds them', (
    tester,
  ) async {
    fakeBackend = backendFrom({
      '/rpc/my_maak_time_slots': [
        {
          'id': 'a',
          'starts_at': _at(2, 17),
          'ends_at': _end(2, 18, 0),
          'booking_id': null,
          'booking_status': null,
          'seeker_name': null,
        },
        {
          'id': 'b',
          'starts_at': _at(3, 18),
          'ends_at': _end(3, 19, 0),
          'booking_id': 'x',
          'booking_status': 'pending',
          'seeker_name': 'Layla',
        },
        {
          'id': 'c',
          'starts_at': _at(5, 20),
          'ends_at': _end(5, 21, 0),
          'booking_id': 'y',
          'booking_status': 'accepted',
          'seeker_name': 'Noura',
        },
      ],
    });
    await tester.runAsync(() => signIn('Rana'));
    await pumpScreen(tester, const AvailabilityPage());
    expect(find.text('Add a time slot'), findsOneWidget);
    expect(find.textContaining('Layla is waiting'), findsOneWidget);
    expect(find.textContaining('Confirmed with Noura'), findsOneWidget);
    // Only the free slot can be removed.
    expect(find.byTooltip('Remove time slot'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'volunteer_availability');
  });

  testScreen('volunteer: empty availability explains what to do', (
    tester,
  ) async {
    fakeBackend = backendFrom({'/rpc/my_maak_time_slots': <Object>[]});
    await tester.runAsync(() => signIn('Rana'));
    await pumpScreen(tester, const AvailabilityPage());
    expect(find.text('No time slots yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testScreen('volunteer: removing a free slot asks first, then calls the server',
      (tester) async {
    fakeBackend = backendFrom({
      '/rpc/my_maak_time_slots': [
        {
          'id': 'free-slot',
          'starts_at': _at(2, 17),
          'ends_at': _end(2, 18, 0),
          'booking_id': null,
          'booking_status': null,
          'seeker_name': null,
        },
      ],
      '/rpc/remove_maak_time_slot': <String, Object>{},
    });
    await tester.runAsync(() => signIn('Rana'));
    await pumpScreen(tester, const AvailabilityPage());
    await _tap(tester, find.byTooltip('Remove time slot'));
    expect(find.text('Remove this time slot?'), findsOneWidget);
    await _shot(tester, 'volunteer_remove_confirm');
    expect(_lastBody('remove_maak_time_slot'), isNull); // not yet
    await _tap(tester, find.text('Remove'));
    expect(_lastBody('remove_maak_time_slot'), {'p_slot_id': 'free-slot'});
  });

  testScreen('help seeker: sees open slots and requests one after confirming', (
    tester,
  ) async {
    fakeBackend = backendFrom({
      '/rpc/volunteer_available_slots': [
        {
          'id': 'slot-1',
          'volunteer_id': 'vol-1',
          'starts_at': _at(2, 17),
          'ends_at': _end(2, 18, 0),
        },
        {
          'id': 'slot-2',
          'volunteer_id': 'vol-1',
          'starts_at': _at(3, 18),
          'ends_at': _end(3, 19, 30),
        },
      ],
      '/rpc/request_maak_session': 'new-booking',
    });
    await tester.runAsync(() => signIn('Layla'));
    await pumpScreen(
      tester,
      const VolunteerSlotsPage(volunteerId: 'vol-1', volunteerName: 'Rana'),
    );
    expect(find.text('Available times'), findsWidgets);
    expect(find.byIcon(Icons.schedule), findsNWidgets(2));
    await _shot(tester, 'seeker_available_times');
    await _tap(tester, find.byIcon(Icons.schedule).first);
    expect(find.text('Request this time?'), findsOneWidget);
    await _shot(tester, 'seeker_request_confirm');
    expect(_lastBody('request_maak_session'), isNull);
    await _tap(tester, find.text('Send request'));
    expect(_lastBody('request_maak_session'), {'p_slot_id': 'slot-1'});
  });

  testScreen('help seeker: a volunteer with no slots shows an empty message', (
    tester,
  ) async {
    fakeBackend = backendFrom({'/rpc/volunteer_available_slots': <Object>[]});
    await tester.runAsync(() => signIn('Layla'));
    await pumpScreen(
      tester,
      const VolunteerSlotsPage(volunteerId: 'vol-1', volunteerName: 'Rana'),
    );
    expect(find.text('No available times'), findsOneWidget);
    expect(find.textContaining('Rana has not shared'), findsOneWidget);
  });

  testScreen('volunteer: sessions show Accept and Decline only when pending', (
    tester,
  ) async {
    fakeBackend = backendFrom({'/rpc/my_maak_sessions': volunteerSessions});
    await tester.runAsync(() => signIn('Rana'));
    await pumpScreen(tester, const SessionsPage(role: 'volunteer'));
    expect(find.text('My available times'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget); // only Layla's pending one
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Awaiting response'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
    // Pending request: Accept/Decline only. Confirmed session: Reschedule + Cancel.
    expect(find.text('Reschedule'), findsNWidgets(1));
    expect(find.text('Cancel'), findsNWidgets(1));
    expect(tester.takeException(), isNull);
    await _shot(tester, 'volunteer_sessions');
  });

  testScreen('volunteer: Accept sends the decision', (tester) async {
    fakeBackend = backendFrom({
      '/rpc/my_maak_sessions': volunteerSessions,
      '/rpc/decide_maak_session': <String, Object>{},
    });
    await tester.runAsync(() => signIn('Rana'));
    await pumpScreen(tester, const SessionsPage(role: 'volunteer'));
    await _tap(tester, find.text('Accept'));
    expect(_lastBody('decide_maak_session'), {
      'p_booking_id': 's1',
      'p_accept': true,
    });
  });

  testScreen('volunteer: Decline asks first, then sends the decision', (
    tester,
  ) async {
    fakeBackend = backendFrom({
      '/rpc/my_maak_sessions': volunteerSessions,
      '/rpc/decide_maak_session': <String, Object>{},
    });
    await tester.runAsync(() => signIn('Rana'));
    await pumpScreen(tester, const SessionsPage(role: 'volunteer'));
    await _tap(tester, find.text('Decline'));
    expect(find.text('Decline this session?'), findsOneWidget);
    await _shot(tester, 'volunteer_decline_confirm');
    expect(_lastBody('decide_maak_session'), isNull);
    await _tap(tester, find.text('Decline').last);
    expect(_lastBody('decide_maak_session'), {
      'p_booking_id': 's1',
      'p_accept': false,
    });
  });

  testScreen('help seeker: sessions show status and Cancel asks first', (
    tester,
  ) async {
    fakeBackend = backendFrom({
      '/rpc/my_maak_sessions': seekerSessions,
      '/rpc/cancel_maak_session': <String, Object>{},
    });
    await tester.runAsync(() => signIn('Layla'));
    await pumpScreen(tester, const SessionsPage(role: 'help_seeker'));
    expect(find.text('My available times'), findsNothing); // volunteers only
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Canceled'), findsOneWidget);
    expect(find.text('Canceled by the other person.'), findsOneWidget);
    await _shot(tester, 'seeker_sessions');
    await _tap(tester, find.text('Cancel').first);
    expect(find.text('Cancel this session?'), findsOneWidget);
    await _shot(tester, 'seeker_cancel_confirm');
    expect(_lastBody('cancel_maak_session'), isNull);
    await _tap(tester, find.text('Cancel session'));
    expect(_lastBody('cancel_maak_session'), {'p_booking_id': 's4'});
  });

  testScreen('help seeker: Reschedule moves the session to a chosen slot', (
    tester,
  ) async {
    fakeBackend = backendFrom({
      '/rpc/my_maak_sessions': seekerSessions,
      '/rpc/volunteer_available_slots': [
        {
          'id': 'new-slot',
          'volunteer_id': 'vol-1',
          'starts_at': _at(8, 17),
          'ends_at': _end(8, 18, 0),
        },
      ],
      '/rpc/reschedule_maak_session': <String, Object>{},
    });
    await tester.runAsync(() => signIn('Layla'));
    await pumpScreen(tester, const SessionsPage(role: 'help_seeker'));
    await _tap(tester, find.text('Reschedule').first);
    expect(find.text('Choose a new time'), findsOneWidget);
    await _shot(tester, 'seeker_reschedule_pick');
    await _tap(tester, find.byIcon(Icons.schedule).first);
    expect(find.text('Move the session here?'), findsOneWidget);
    await _tap(tester, find.text('Move session'));
    expect(_lastBody('reschedule_maak_session'), {
      'p_booking_id': 's4',
      'p_new_slot_id': 'new-slot',
    });
  });

  testScreen('a server error is shown in plain words', (tester) async {
    fakeBackend = backendFrom({
      '/rpc/volunteer_available_slots': [
        {
          'id': 'slot-1',
          'volunteer_id': 'vol-1',
          'starts_at': _at(2, 17),
          'ends_at': _end(2, 18, 0),
        },
      ],
      '/rpc/request_maak_session': (request) => Future.value(
        jsonResponse(request, {
          'code': 'P0001',
          'message': 'slot_unavailable',
        }, status: 400),
      ),
    });
    await tester.runAsync(() => signIn('Layla'));
    await pumpScreen(
      tester,
      const VolunteerSlotsPage(volunteerId: 'vol-1', volunteerName: 'Rana'),
    );
    await _tap(tester, find.byIcon(Icons.schedule).first);
    await _tap(tester, find.text('Send request'));
    expect(
      find.text('This time is no longer available. Choose another time.'),
      findsOneWidget,
    );
    await _shot(tester, 'seeker_slot_taken_error');
  });
}
