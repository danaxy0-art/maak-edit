// Sprint 4 US1/US2: widget checks for lib/frontend/redesign/ratings.dart and
// where it appears. The database rules are covered by
// tests/database/volunteer_ratings_test.mjs.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/backend/services/volunteer_stats_service.dart';
import 'package:maak_app/frontend/redesign/ratings.dart';
import 'package:maak_app/frontend/redesign/support.dart';

import 'helpers/screen_harness.dart';

List<http.Request> _calls(String rpc) =>
    sentRequests.where((r) => r.url.path.endsWith('/rpc/$rpc')).toList();

Future<http.Response> Function(http.Request) _error(String message) =>
    (request) async => jsonResponse(request, {
      'code': 'P0001',
      'message': message,
      'details': null,
      'hint': null,
    }, status: 400);

Widget _card() => const Scaffold(
  body: Column(
    children: [RateVolunteerCard(requestId: 'req-1', volunteerName: 'Sara')],
  ),
);

Widget _summary(String id) => Scaffold(
  body: Center(child: VolunteerStatsLine(volunteerId: id)),
);

Map<String, Object?> _stats(String id, int count, [double? average]) => {
  'volunteer_id': id,
  'rating_count': count,
  'average_rating': average,
};

/// A server timestamp [h] hours from now, in UTC like the database sends it.
String _inHours(num h) => DateTime.now()
    .toUtc()
    .add(Duration(minutes: (h * 60).round()))
    .toIso8601String();

/// Signs in as a member with [id] (the shared harness signs in one fixed id).
Future<void> _signInAs(String id, String name) async {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(days: 1));
  final seconds = exp.millisecondsSinceEpoch ~/ 1000;
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token':
          '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': id, 'exp': seconds})}.sig',
      'refresh_token': 'refresh',
      'token_type': 'bearer',
      'expires_in': 86400,
      'expires_at': seconds,
      'user': {
        'id': id,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': '$name@example.com',
        'app_metadata': {},
        'user_metadata': {'full_name': name},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

PostgrestException _pg(String message) =>
    PostgrestException(message: message, code: 'P0001');

void main() {
  setUpAll(setUpScreenHarness);

  group('RatingError (central mapping of server identifiers)', () {
    test('each database identifier maps to one known error', () {
      for (final e in RatingError.values) {
        expect(RatingError.of(_pg(e.code)), e);
        expect(ratingErrorText[e], isNotEmpty, reason: 'every error has text');
      }
      expect(RatingError.of(_pg(' already_rated ')), RatingError.alreadyRated);
    });
    test('anything else is not a rating error', () {
      expect(RatingError.of(_pg('something_else')), isNull);
      expect(
        RatingError.of(_pg('not_already_rated_at_all')),
        isNull,
        reason: 'exact identifiers, not substrings',
      );
      expect(RatingError.of(Exception('already_rated')), isNull);
    });
    test('only bad input keeps the editor open; the rest reload', () {
      expect(RatingError.unchanged.staleState, isFalse);
      expect(RatingError.invalidStars.staleState, isFalse);
      for (final e in [
        RatingError.alreadyRated,
        RatingError.notAllowed,
        RatingError.correctionNotAllowed,
        RatingError.notFound,
      ]) {
        expect(e.staleState, isTrue);
      }
    });
  });

  group('server-driven correction wording', () {
    test('window text comes from the server value', () {
      expect(correctionWindowText(const Duration(hours: 24)), '24 hours');
      expect(correctionWindowText(const Duration(hours: 1)), '1 hour');
      expect(correctionWindowText(const Duration(minutes: 30)), '30 minutes');
    });
    test('deadline is parsed as UTC and shown in local time', () {
      final s = RatingStatus.fromJson({
        'state': 'rated',
        'can_correct': true,
        'correct_until': '2026-11-27T10:00:00Z',
        'correction_window_seconds': 86400,
      });
      expect(s.correctUntil!.isUtc, isFalse);
      expect(
        s.correctUntil!.toUtc(),
        DateTime.utc(2026, 11, 27, 10),
        reason: 'same instant, converted to the device zone',
      );
      expect(s.correctionWindow, const Duration(hours: 24));
      expect(s.canCorrectAt(DateTime.utc(2026, 11, 27, 9, 59)), isTrue);
      expect(s.canCorrectAt(DateTime.utc(2026, 11, 27, 10)), isFalse);
    });
  });
  setUp(VolunteerStatsService.resetCache);

  group('StarRatingInput', () {
    testWidgets('five labelled 48 pt stars; tapping reports the value', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StarRatingInput(value: 2, onChanged: (v) => picked = v),
          ),
        ),
      );
      for (var i = 1; i <= 5; i++) {
        final star = find.byKey(ValueKey('rating_star_$i'));
        expect(tester.getSize(star), const Size(48, 48));
      }
      expect(
        find.bySemanticsLabel('3 stars, Good'),
        findsOneWidget,
        reason: 'each star is announced with its value and meaning',
      );
      await tester.tap(find.byKey(const ValueKey('rating_star_4')));
      expect(picked, 4);
    });
  });

  group('VolunteerStatsLine', () {
    testScreen('no ratings: "No ratings yet", never zero stars', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': [_stats('v1', 0)],
      });
      await pumpScreen(tester, _summary('v1'));
      expect(find.text('No ratings yet'), findsOneWidget);
      expect(find.byType(StarsDisplay), findsNothing);
    });

    testScreen('below the minimum: count only, no average', (tester) async {
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': [_stats('v1', 2)],
      });
      await pumpScreen(tester, _summary('v1'));
      expect(find.text('2 ratings'), findsOneWidget);
      expect(find.byType(StarsDisplay), findsNothing);
    });

    testScreen('with an average: one decimal, stars and count', (tester) async {
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': [_stats('v1', 12, 4.6)],
      });
      await pumpScreen(tester, _summary('v1'));
      expect(find.text('4.6'), findsOneWidget);
      expect(find.text('(12 ratings)'), findsOneWidget);
      expect(find.byType(StarsDisplay), findsOneWidget);
      expect(
        find.bySemanticsLabel('Rated 4.6 out of 5 from 12 ratings'),
        findsOneWidget,
      );
    });

    testScreen('no summary for this member, or a failed load: shows nothing', (
      tester,
    ) async {
      await pumpScreen(tester, _summary('v1')); // backend answers []
      expect(
        find.byKey(const ValueKey('volunteer_rating_summary')),
        findsNothing,
      );
      VolunteerStatsService.resetCache();
      fakeBackend = backendFrom({'/rpc/maak_volunteer_stats': _error('boom')});
      await pumpScreen(tester, _summary('v2'));
      expect(
        find.byKey(const ValueKey('volunteer_rating_summary')),
        findsNothing,
      );
    });

    testScreen('a list of volunteers loads every summary in one request', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': [
          _stats('v1', 3, 4.0),
          _stats('v2', 0),
          _stats('v3', 1),
        ],
      });
      await pumpScreen(
        tester,
        const Scaffold(
          body: Column(
            children: [
              VolunteerStatsLine(volunteerId: 'v1'),
              VolunteerStatsLine(volunteerId: 'v2'),
              VolunteerStatsLine(volunteerId: 'v3'),
              VolunteerStatsLine(volunteerId: 'v1'),
            ],
          ),
        ),
      );
      final calls = _calls('maak_volunteer_stats');
      expect(calls, hasLength(1));
      expect(
        (jsonDecode(calls.single.body)['p_volunteer_ids'] as List).toSet(),
        {'v1', 'v2', 'v3'},
      );
      expect(find.text('4.0'), findsNWidgets(2));
      expect(find.text('No ratings yet'), findsOneWidget);
      expect(find.text('1 rating'), findsOneWidget);
    });
  });

  group('RateVolunteerCard', () {
    testScreen('eligible: pick stars, submit, see the saved rating', (
      tester,
    ) async {
      var rated = false;
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {'state': 'eligible', 'volunteer_id': 'v1'},
        '/rpc/rate_maak_volunteer': (http.Request r) async {
          rated = true;
          return jsonResponse(r, {
            'state': 'rated',
            'stars': 4,
            'volunteer_id': 'v1',
          });
        },
      });
      await pumpScreen(tester, _card());
      expect(find.text('How was your support from Sara?'), findsOneWidget);
      final submit = find.widgetWithText(InkWell, 'Submit rating');
      await tester.tap(find.text('Submit rating'), warnIfMissed: false);
      await settle(tester);
      expect(rated, isFalse, reason: 'nothing is sent before a star is chosen');

      await tester.tap(find.byKey(const ValueKey('rating_star_4')));
      await tester.pump();
      expect(find.text('Very good'), findsOneWidget);
      await tester.tap(find.text('Submit rating'));
      await settle(tester);

      expect(jsonDecode(_calls('rate_maak_volunteer').single.body), {
        'p_request_id': 'req-1',
        'p_stars': 4,
      });
      expect(
        find.text('You rated Sara 4 of 5. Thank you for your feedback.'),
        findsOneWidget,
      );
      expect(
        find.text('Thank you. Your rating was submitted.'),
        findsOneWidget,
      );
      expect(find.byType(StarRatingInput), findsNothing);
      expect(submit, findsNothing);
    });

    testScreen('a refused submission shows a plain message and no success', (
      tester,
    ) async {
      var statusCalls = 0;
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': (http.Request r) async => jsonResponse(
          r,
          statusCalls++ == 0
              ? {'state': 'eligible', 'volunteer_id': 'v1'}
              : {'state': 'rated', 'stars': 2, 'volunteer_id': 'v1'},
        ),
        '/rpc/rate_maak_volunteer': _error('already_rated'),
      });
      await pumpScreen(tester, _card());
      await tester.tap(find.byKey(const ValueKey('rating_star_5')));
      await tester.pump();
      await tester.tap(find.text('Submit rating'));
      await settle(tester);
      expect(find.text('Thank you. Your rating was submitted.'), findsNothing);
      // Reloaded from the server: the rating saved on another device.
      expect(
        find.text('You rated Sara 2 of 5. Thank you for your feedback.'),
        findsOneWidget,
      );
    });

    testScreen('a network failure keeps the choice so the member can retry', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {'state': 'eligible', 'volunteer_id': 'v1'},
        '/rpc/rate_maak_volunteer': (http.Request r) async =>
            throw http.ClientException('offline'),
      });
      await pumpScreen(tester, _card());
      await tester.tap(find.byKey(const ValueKey('rating_star_3')));
      await tester.pump();
      await tester.tap(find.text('Submit rating'));
      await settle(tester);
      expect(find.byKey(const ValueKey('rating_error')), findsOneWidget);
      expect(find.text('Thank you. Your rating was submitted.'), findsNothing);
      expect(find.byType(StarRatingInput), findsOneWidget);
      expect(find.text('Good'), findsOneWidget, reason: '3 stars still chosen');
    });

    testScreen('already rated: shows the rating, no input', (tester) async {
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {
          'state': 'rated',
          'stars': 5,
          'volunteer_id': 'v1',
        },
      });
      await pumpScreen(tester, _card());
      expect(
        find.text('You rated Sara 5 of 5. Thank you for your feedback.'),
        findsOneWidget,
      );
      expect(find.byType(StarRatingInput), findsNothing);
    });

    testScreen('volunteer never replied: explains why rating is unavailable', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {'state': 'no_support', 'volunteer_id': 'v1'},
      });
      await pumpScreen(tester, _card());
      expect(
        find.text(
          'Ratings are available once the volunteer has replied in the conversation.',
        ),
        findsOneWidget,
      );
      expect(find.byType(StarRatingInput), findsNothing);
    });

    for (final state in [
      'not_seeker',
      'unavailable',
      'not_ended',
      'restricted',
    ]) {
      testScreen('$state: nothing is shown', (tester) async {
        fakeBackend = backendFrom({
          '/rpc/my_maak_rating': {'state': state},
        });
        await pumpScreen(tester, _card());
        expect(find.byKey(const ValueKey('rate_volunteer_card')), findsNothing);
      });
    }

    testScreen('a failed load offers Retry', (tester) async {
      var calls = 0;
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': (http.Request r) async {
          if (calls++ == 0) throw http.ClientException('offline');
          return jsonResponse(r, {'state': 'eligible', 'volunteer_id': 'v1'});
        },
      });
      await pumpScreen(tester, _card());
      expect(
        find.text('Could not load the rating for this conversation.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text('How was your support from Sara?'), findsOneWidget);
    });

    testScreen('submitting refreshes that volunteer\'s summary', (
      tester,
    ) async {
      var statsCalls = 0;
      fakeBackend = backendFrom({
        '/rpc/maak_volunteer_stats': (http.Request r) async => jsonResponse(r, [
          statsCalls++ == 0 ? _stats('v1', 2) : _stats('v1', 3, 4.3),
        ]),
        '/rpc/my_maak_rating': {'state': 'eligible', 'volunteer_id': 'v1'},
        '/rpc/rate_maak_volunteer': {
          'state': 'rated',
          'stars': 4,
          'volunteer_id': 'v1',
        },
      });
      await pumpScreen(tester, _summary('v1'));
      expect(find.text('2 ratings'), findsOneWidget);
      await pumpScreen(tester, _card());
      await tester.tap(find.byKey(const ValueKey('rating_star_4')));
      await tester.pump();
      await tester.tap(find.text('Submit rating'));
      await settle(tester);
      await pumpScreen(tester, _summary('v1'));
      expect(find.text('4.3'), findsOneWidget);
    });

    testScreen('correction: change once, then the rating is final', (
      tester,
    ) async {
      var corrected = false;
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {
          'state': 'rated',
          'stars': 2,
          'volunteer_id': 'v1',
          'can_correct': true,
          'correct_until': _inHours(2),
        },
        '/rpc/correct_maak_rating': (http.Request r) async {
          corrected = true;
          return jsonResponse(r, {
            'state': 'rated',
            'stars': 4,
            'volunteer_id': 'v1',
            'can_correct': false,
          });
        },
      });
      await pumpScreen(tester, _card());
      await tester.tap(find.text('Change rating (once)'));
      await tester.pump();
      expect(find.text('Change your rating of Sara'), findsOneWidget);
      expect(find.text('Fair'), findsOneWidget, reason: 'starts at 2 stars');

      // Cancel returns to the saved rating without sending anything.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(corrected, isFalse);
      expect(
        find.text('You rated Sara 2 of 5. Thank you for your feedback.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Change rating (once)'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rating_star_4')));
      await tester.pump();
      await tester.tap(find.text('Save change'));
      await settle(tester);
      expect(jsonDecode(_calls('correct_maak_rating').single.body), {
        'p_request_id': 'req-1',
        'p_stars': 4,
      });
      expect(
        _calls('rate_maak_volunteer'),
        isEmpty,
        reason: 'a correction never creates a new rating',
      );
      expect(find.text('Your rating was changed.'), findsOneWidget);
      expect(
        find.text('You rated Sara 4 of 5. Thank you for your feedback.'),
        findsOneWidget,
      );
      expect(find.text('Change rating (once)'), findsNothing);
    });

    testScreen('no correction offered once it is used or the window passed', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {
          'state': 'rated',
          'stars': 3,
          'volunteer_id': 'v1',
          'can_correct': false,
        },
      });
      await pumpScreen(tester, _card());
      expect(find.text('Change rating (once)'), findsNothing);
    });

    testScreen('a refused correction explains it and shows the final rating', (
      tester,
    ) async {
      var loads = 0;
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': (http.Request r) async => jsonResponse(r, {
          'state': 'rated',
          'stars': 2,
          'volunteer_id': 'v1',
          'can_correct': loads++ == 0,
          'correct_until': _inHours(2),
        }),
        '/rpc/correct_maak_rating': _error('correction_not_allowed'),
      });
      await pumpScreen(tester, _card());
      await tester.tap(find.text('Change rating (once)'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rating_star_5')));
      await tester.pump();
      await tester.tap(find.text('Save change'));
      await settle(tester);
      expect(
        find.text('This rating can no longer be changed.'),
        findsOneWidget,
      );
      expect(find.text('Your rating was changed.'), findsNothing);
      expect(
        find.text('You rated Sara 2 of 5. Thank you for your feedback.'),
        findsOneWidget,
      );
      expect(find.text('Change rating (once)'), findsNothing);
    });

    testScreen('choosing the same stars keeps the editor open', (tester) async {
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {
          'state': 'rated',
          'stars': 3,
          'volunteer_id': 'v1',
          'can_correct': true,
          'correct_until': _inHours(2),
        },
        '/rpc/correct_maak_rating': _error('rating_unchanged'),
      });
      await pumpScreen(tester, _card());
      await tester.tap(find.text('Change rating (once)'));
      await tester.pump();
      await tester.tap(find.text('Save change'));
      await settle(tester);
      expect(
        find.text('Choose a different number of stars to change your rating.'),
        findsOneWidget,
      );
      expect(find.text('Save change'), findsOneWidget);
    });
  });

  testScreen('volunteer directory cards show each volunteer\'s rating', (
    tester,
  ) async {
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
      '/rpc/maak_volunteer_stats': [_stats('v1', 5, 4.8), _stats('v2', 0)],
    });
    await pumpScreen(tester, const VolunteerDirectoryPage());
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('No ratings yet'), findsOneWidget);
    expect(_calls('maak_volunteer_stats'), hasLength(1));
  });

  group('correction deadline on screen', () {
    Map<String, Object?> rated(String? until, {bool can = true}) => {
      'state': 'rated',
      'stars': 2,
      'volunteer_id': 'v1',
      'can_correct': can,
      'correct_until': until,
      'correction_window_seconds': 86400,
    };

    testScreen('shows the server deadline in local time', (tester) async {
      final until = DateTime.now().add(const Duration(hours: 2));
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': rated(until.toUtc().toIso8601String()),
      });
      await pumpScreen(tester, _card());
      final context = tester.element(find.byType(RateVolunteerCard));
      final expected = correctionDeadlineText(context, until);
      expect(
        expected,
        anyOf(startsWith('today at '), startsWith('tomorrow at ')),
      );
      expect(
        find.text('You can change it once, until $expected.'),
        findsOneWidget,
      );
      // The local clock time of the server instant, e.g. "3:45 PM".
      final clock = MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(until));
      expect(expected, endsWith(clock));
    });

    testScreen('a deadline days away is shown with its date', (tester) async {
      final until = DateTime.now().add(const Duration(days: 3));
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': rated(until.toUtc().toIso8601String()),
      });
      await pumpScreen(tester, _card());
      final context = tester.element(find.byType(RateVolunteerCard));
      final date = MaterialLocalizations.of(context).formatMediumDate(until);
      expect(find.textContaining('until $date at '), findsOneWidget);
    });

    testScreen('an expired deadline is never offered, even if flagged', (
      tester,
    ) async {
      fakeBackend = backendFrom({'/rpc/my_maak_rating': rated(_inHours(-0.1))});
      await pumpScreen(tester, _card());
      expect(find.text('Change rating (once)'), findsNothing);
      expect(find.byKey(const ValueKey('correction_deadline')), findsNothing);
    });

    testScreen('no deadline from the server: no correction offered', (
      tester,
    ) async {
      fakeBackend = backendFrom({'/rpc/my_maak_rating': rated(null)});
      await pumpScreen(tester, _card());
      expect(find.text('Change rating (once)'), findsNothing);
    });

    testScreen('the offer disappears when the deadline passes on screen', (
      tester,
    ) async {
      // One controlled clock for both the deadline check and the one-shot
      // timer: nothing here depends on how fast the machine is.
      var now = DateTime(2026, 11, 26, 12);
      RateVolunteerCard.clock = () => now;
      addTearDown(() => RateVolunteerCard.clock = DateTime.now);
      final until = now.add(const Duration(seconds: 30));
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': rated(until.toUtc().toIso8601String()),
      });
      await pumpScreen(tester, _card());
      await tester.tap(find.text('Change rating (once)'));
      await tester.pump();
      expect(find.text('Save change'), findsOneWidget);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31)); // fires the timer
      expect(find.text('Save change'), findsNothing);
      expect(find.text('Change rating (once)'), findsNothing);
      expect(_calls('my_maak_rating'), hasLength(1), reason: 'no polling');
    });

    testScreen('before rating, the window is worded from the server', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {
          'state': 'eligible',
          'volunteer_id': 'v1',
          'correction_window_seconds': 1800,
        },
      });
      await pumpScreen(tester, _card());
      expect(
        find.textContaining(
          'You can change your rating once within 30 minutes.',
        ),
        findsOneWidget,
      );
    });

    testScreen('before rating, no window from the server: no promise made', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        '/rpc/my_maak_rating': {'state': 'eligible', 'volunteer_id': 'v1'},
      });
      await pumpScreen(tester, _card());
      expect(find.textContaining('You can change your rating'), findsNothing);
    });
  });

  group('account switch while a summary request is in flight', () {
    const a = '00000000-0000-4000-8000-00000000000a';
    const b = '00000000-0000-4000-8000-00000000000b';

    // The first stats request (account A) is held open until released.
    Future<void> race(WidgetTester tester, {required bool aFails}) async {
      final held = Completer<http.Response>();
      fakeBackend = (request) {
        if (!request.url.path.endsWith('/rpc/maak_volunteer_stats')) {
          return null;
        }
        if (_calls('maak_volunteer_stats').length == 1) return held.future;
        return Future.value(jsonResponse(request, [_stats('v1', 7, 4.0)]));
      };
      // Signing in runs in the test zone (as the shared harness does); only
      // the network round trips run on the real event loop.
      await _signInAs(a, 'Amal');
      late Future<VolunteerStats?> forA;
      await tester.runAsync(() async {
        forA = VolunteerStatsService.stats('v1');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(
        _calls('maak_volunteer_stats'),
        hasLength(1),
        reason: 'A in flight',
      );

      await _signInAs(b, 'Basma');
      await tester.runAsync(() async {
        final forB = await VolunteerStatsService.stats('v1');
        expect(forB?.ratingCount, 7);

        // A's late answer arrives after B signed in.
        final req = sentRequests.firstWhere(
          (r) => r.url.path.endsWith('/rpc/maak_volunteer_stats'),
        );
        held.complete(
          aFails
              ? jsonResponse(req, {
                  'message': 'boom',
                  'code': '500',
                }, status: 500)
              : jsonResponse(req, [_stats('v1', 99, 1.0)]),
        );
      });
      // A's response chain started under the test zone: let both zones run.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.runAsync(() async {
        final lateA = await forA;
        expect(
          lateA?.ratingCount,
          aFails ? isNull : 99,
          reason: 'A gets its own answer',
        );

        // B still sees B's summary, from the cache, with no extra request.
        final again = await VolunteerStatsService.stats('v1');
        expect(again?.ratingCount, 7);
        expect(again?.averageRating, 4.0);
        expect(_calls('maak_volunteer_stats'), hasLength(2));
      });
    }

    testScreen('a late success for the old account never reaches the cache', (
      tester,
    ) async {
      VolunteerStatsService.resetCache();
      await race(tester, aFails: false);
    });

    testScreen('a late failure for the old account never evicts the new one', (
      tester,
    ) async {
      VolunteerStatsService.resetCache();
      await race(tester, aFails: true);
    });
  });
}
