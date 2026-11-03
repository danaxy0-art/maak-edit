import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:maak_app/frontend/redesign/matching_page.dart';
import 'package:maak_app/frontend/redesign/shell.dart';
import 'package:maak_app/frontend/redesign/support.dart';

import 'helpers/screen_harness.dart';

// Help Seeker screens (discovery, matching, volunteer profile, My journey)
// and the app navigation bar, in every state, at phone and tablet sizes.
// Screenshots land in test/goldens/seeker/.

const _phone = Size(390, 844);
const _tablet = Size(834, 1194);

const volunteers = [
  {
    'user_id': '00000000-0000-0000-0000-000000000011',
    'full_name': 'Sara Al-Harbi',
    'condition': 'Type 1 diabetes',
    'language': 'Arabic',
    'description':
        'Diagnosed at 14. I know how tiring the first year of carb counting and night lows can be, and I am happy to talk through school, work and travel.',
  },
  {
    'user_id': '00000000-0000-0000-0000-000000000012',
    'full_name': 'Noura Saleh',
    'condition': 'Celiac disease, Crohn’s disease',
    'language': 'English',
    'description':
        'Living with Crohn’s for nine years and celiac for five. Eating out, flare-ups and explaining it to family are all things I can help with.',
  },
  {
    'user_id': '00000000-0000-0000-0000-000000000013',
    'full_name': 'Reem Khalid',
    'condition': 'Asthma',
    'language': 'Arabic',
    'description': 'Asthma since childhood; I coach a running club now.',
  },
];

const _diabetes = {'id': 'c1', 'name': 'Type 1 diabetes'};
const _celiac = {'id': 'c2', 'name': 'Celiac disease'};

Map<String, dynamic> matchResult({bool empty = false}) => {
  'mode': 'conditions',
  'notice': 'Ranked by shared conditions, then preferred language.',
  'seeker_conditions': [_diabetes, _celiac],
  'matches': empty
      ? []
      : [
          {
            ...volunteers[0],
            'conditions': [_diabetes],
            'shared_conditions': [_diabetes],
            'coverage_percent': 50,
            'experience_similarity': null,
          },
          {
            ...volunteers[1],
            'conditions': [
              _celiac,
              {'id': 'c3', 'name': 'Crohn’s disease'},
            ],
            'shared_conditions': [_celiac],
            'coverage_percent': 50,
            'experience_similarity': null,
          },
        ],
  'complementary': empty
      ? []
      : [
          {
            'user_id': volunteers[0]['user_id'],
            'covers': [_diabetes],
          },
          {
            'user_id': volunteers[1]['user_id'],
            'covers': [_celiac],
          },
        ],
  'uncovered_conditions': empty ? [_diabetes, _celiac] : [],
};

const requests = [
  {
    'id': '00000000-0000-0000-0000-0000000000a1',
    'status': 'pending',
    'contact_name': 'Reem Khalid',
    'created_at': '2026-10-27T10:00:00Z',
  },
  {
    'id': '00000000-0000-0000-0000-0000000000a2',
    'status': 'accepted',
    'contact_name': 'Sara Al-Harbi',
    'created_at': '2026-10-20T10:00:00Z',
    'last_message': 'Happy to help. How are your mornings going this week?',
  },
  {
    'id': '00000000-0000-0000-0000-0000000000a3',
    'status': 'declined',
    'contact_name': 'Noura Saleh',
    'created_at': '2026-10-12T10:00:00Z',
  },
  {
    'id': '00000000-0000-0000-0000-0000000000a4',
    'status': 'canceled',
    'contact_name': 'Lama Mansour',
    'created_at': '2026-10-02T10:00:00Z',
  },
];

Future<http.Response> _fails(http.Request r) => Future.value(
  jsonResponse(r, {'message': 'unavailable', 'code': '503'}, status: 503),
);
Future<http.Response> _hangs(http.Request r) => neverResponds();
Future<http.Response> _ok(http.Request r) => Future.value(jsonResponse(r, {}));

final _seekerData = {
  '/rpc/browse_volunteers': volunteers,
  '/rpc/my_support_requests': requests,
  '/match-volunteers': matchResult(),
};

class _Case {
  final Widget Function() screen;
  final Map<String, Object> backend;
  final Future<void> Function(WidgetTester)? interact;
  final List<Size> sizes;
  final bool largeText;
  const _Case(
    this.screen,
    this.backend, {
    this.interact,
    this.sizes = const [_phone],
    this.largeText = false,
  });
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -3000));
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setUpScreenHarness);

  final cases = <String, _Case>{
    // Volunteer discovery
    'discovery': _Case(
      VolunteerDirectoryPage.new,
      _seekerData,
      sizes: [_phone, _tablet],
      largeText: true,
    ),
    'discovery_loading': _Case(VolunteerDirectoryPage.new, {
      '/rpc/browse_volunteers': _hangs,
    }),
    'discovery_error': _Case(VolunteerDirectoryPage.new, {
      '/rpc/browse_volunteers': _fails,
    }),
    'discovery_empty': _Case(VolunteerDirectoryPage.new, {
      '/rpc/browse_volunteers': <Object>[],
    }),
    'discovery_no_results': _Case(
      VolunteerDirectoryPage.new,
      _seekerData,
      interact: (tester) async {
        await tester.enterText(find.byType(TextField).first, 'lupus');
        await settle(tester);
      },
    ),
    // Matching
    'matching': _Case(
      MatchingPage.new,
      _seekerData,
      sizes: [_phone, _tablet],
      largeText: true,
    ),
    'matching_results': _Case(
      MatchingPage.new,
      _seekerData,
      interact: _scrollToEnd,
    ),
    'matching_loading': _Case(MatchingPage.new, {'/match-volunteers': _hangs}),
    'matching_error': _Case(MatchingPage.new, {'/match-volunteers': _fails}),
    'matching_empty': _Case(MatchingPage.new, {
      '/match-volunteers': matchResult(empty: true),
    }, interact: _scrollToEnd),
    // Volunteer profile
    'profile': _Case(
      () => VolunteerDetailPage(volunteer: volunteers[0]),
      _seekerData,
      sizes: [_phone, _tablet],
      largeText: true,
    ),
    'profile_from_matching': _Case(
      () => VolunteerDetailPage(
        volunteer: {
          ...(matchResult()['matches'] as List).first as Map<String, dynamic>,
          'condition': 'Type 1 diabetes',
        },
      ),
      _seekerData,
    ),
    'profile_sent': _Case(
      () => VolunteerDetailPage(volunteer: volunteers[0]),
      {'/rpc/request_peer_support': _ok},
      interact: (tester) =>
          _tap(tester, find.widgetWithText(InkWell, 'Request support').last),
    ),
    'profile_error': _Case(
      () => VolunteerDetailPage(volunteer: volunteers[0]),
      {'/rpc/request_peer_support': _fails},
      interact: (tester) =>
          _tap(tester, find.widgetWithText(InkWell, 'Request support').last),
    ),
    // My journey (support requests)
    'journey': _Case(
      JourneyPage.new,
      _seekerData,
      sizes: [_phone, _tablet],
      largeText: true,
    ),
    'journey_loading': _Case(JourneyPage.new, {
      '/rpc/my_support_requests': _hangs,
    }),
    'journey_error': _Case(JourneyPage.new, {
      '/rpc/my_support_requests': _fails,
    }),
    'journey_empty': _Case(JourneyPage.new, {
      '/rpc/my_support_requests': <Object>[],
    }),
    'journey_cancel_dialog': _Case(
      JourneyPage.new,
      _seekerData,
      interact: (tester) => _tap(tester, find.text('Cancel request').first),
    ),
    'journey_canceled': _Case(
      JourneyPage.new,
      {..._seekerData, '/rpc/cancel_support_request': _ok},
      interact: (tester) async {
        await _tap(tester, find.text('Cancel request').first);
        await _tap(tester, find.text('Cancel request').last);
      },
    ),
  };

  for (final c in cases.entries) {
    final variants = <(String, Size, double)>[
      for (final size in c.value.sizes)
        (size == _tablet ? 'tablet' : 'phone', size, 1.0),
      if (c.value.largeText) ('phone_2.0x', _phone, 2.0),
    ];
    for (final (label, size, scale) in variants) {
      testScreen('${c.key} $label', (tester) async {
        fakeBackend = backendFrom(c.value.backend);
        await tester.runAsync(() => signIn('Layla'));
        await pumpScreen(
          tester,
          c.value.screen(),
          size: size,
          textScale: scale,
        );
        await c.value.interact?.call(tester);
        expect(tester.takeException(), isNull);
        await shot(tester, 'goldens/seeker/${c.key}_$label.png');
      });
    }
  }

  // The shared navigation bar under redesigned and not-yet-redesigned tabs.
  final shells = <String, (String, String?, Size)>{
    'nav_seeker_home': ('help_seeker', null, _phone),
    'nav_seeker_journey': ('help_seeker', 'Journey', _phone),
    'nav_volunteer_requests': ('volunteer', 'Requests', _phone),
    'nav_seeker_tablet': ('help_seeker', null, _tablet),
  };
  for (final s in shells.entries) {
    final (role, tab, size) = s.value;
    testScreen(s.key, (tester) async {
      fakeBackend = backendFrom(_seekerData);
      await tester.runAsync(() => signIn('Layla'));
      await pumpScreen(tester, AppShell(role: role), size: size);
      if (tab != null) await _tap(tester, find.text(tab).last);
      expect(tester.takeException(), isNull);
      await shot(tester, 'goldens/seeker/${s.key}.png');
    });
  }

  group('behaviour', () {
    testScreen('discovery keeps search rules and destinations', (tester) async {
      fakeBackend = backendFrom(_seekerData);
      await tester.runAsync(() => signIn('Layla'));
      await pumpScreen(tester, const VolunteerDirectoryPage());
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, 100);
      expect(find.text('0/100'), findsNothing);
      expect(find.text('3 volunteers'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ARABIC');
      await settle(tester);
      expect(find.text('2 volunteers'), findsOneWidget);
      expect(find.text('Noura Saleh'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await settle(tester);

      await _tap(tester, find.text('Recommended matches'));
      expect(find.byType(MatchingPage), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      await _tap(tester, find.text('Noura Saleh'));
      expect(find.byType(VolunteerDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testScreen('matching keeps AI off until the member opts in', (
      tester,
    ) async {
      fakeBackend = backendFrom(_seekerData);
      await tester.runAsync(() => signIn('Layla'));
      await pumpScreen(tester, const MatchingPage());
      List<bool> aiFlags() => [
        for (final r in sentRequests)
          if (r.url.path.endsWith('/match-volunteers'))
            (jsonDecode(r.body) as Map)['use_ai'] as bool,
      ];
      expect(aiFlags(), [false]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        find.text(
          'Optional: sends your support description and opted-in volunteers’ descriptions to Google Gemini. Names, emails and verification documents are not sent. Avoid identifying details in your description.',
        ),
        findsOneWidget,
      );
      expect(find.text('Type 1 diabetes'), findsWidgets);

      await _tap(tester, find.text('Find matches'));
      expect(aiFlags(), [false, false]);
      await _tap(tester, find.byType(Switch));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(aiFlags(), [
        false,
        false,
      ], reason: 'switching alone sends nothing');
      await _tap(tester, find.text('Find matches'));
      expect(aiFlags(), [false, false, true]);

      await _tap(tester, find.text('Sara Al-Harbi').last);
      expect(find.byType(VolunteerDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testScreen('profile sends one request to the chosen volunteer', (
      tester,
    ) async {
      fakeBackend = backendFrom({'/rpc/request_peer_support': _ok});
      await tester.runAsync(() => signIn('Layla'));
      await pumpScreen(tester, VolunteerDetailPage(volunteer: volunteers[1]));
      await _tap(tester, find.text('Request support'));
      final sent = sentRequests
          .where((r) => r.url.path.endsWith('/rpc/request_peer_support'))
          .toList();
      expect(sent, hasLength(1));
      expect(jsonDecode(sent.single.body), {
        'p_volunteer_id': volunteers[1]['user_id'],
      });
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Support request sent.'), findsOneWidget);
      await _tap(tester, find.text('Request sent'));
      expect(
        sentRequests.where(
          (r) => r.url.path.endsWith('/rpc/request_peer_support'),
        ),
        hasLength(1),
      );
    });

    testScreen('journey groups by status and keeps every action', (
      tester,
    ) async {
      fakeBackend = backendFrom({
        ..._seekerData,
        '/rpc/cancel_support_request': _ok,
      });
      await tester.runAsync(() => signIn('Layla'));
      await pumpScreen(tester, const JourneyPage());
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Active'), lessThan(top('Reem Khalid')));
      expect(top('Sara Al-Harbi'), lessThan(top('Past')));
      expect(top('Past'), lessThan(top('Noura Saleh')));
      expect(top('Past'), lessThan(top('Lama Mansour')));
      for (final label in [
        'Awaiting response',
        'Connected',
        'Declined',
        'Canceled',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Sent 27 Oct 2026'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);

      await _tap(tester, find.text('Cancel request'));
      await _tap(tester, find.text('Keep request'));
      expect(
        sentRequests.where((r) => r.url.path.contains('cancel_support')),
        isEmpty,
      );
      await _tap(tester, find.text('Cancel request'));
      await _tap(tester, find.text('Cancel request').last);
      final cancel = sentRequests.singleWhere(
        (r) => r.url.path.endsWith('/rpc/cancel_support_request'),
      );
      expect(jsonDecode(cancel.body), {'p_request_id': requests[0]['id']});

      await _tap(tester, find.text('Open conversation'));
      expect(find.byType(ConversationPage), findsOneWidget);
    });

    testScreen('empty journey leads to matching', (tester) async {
      fakeBackend = backendFrom({'/rpc/my_support_requests': <Object>[]});
      await tester.runAsync(() => signIn('Layla'));
      await pumpScreen(tester, const JourneyPage());
      await _tap(tester, find.text('Find my matches'));
      expect(find.byType(MatchingPage), findsOneWidget);
    });

    testScreen('navigation keeps tabs, labels and destinations', (
      tester,
    ) async {
      fakeBackend = backendFrom(_seekerData);
      await tester.runAsync(() => signIn('Layla'));
      await pumpScreen(tester, const AppShell(role: 'help_seeker'));
      for (final label in ['Home', 'Journey', 'Messages', 'Profile']) {
        expect(find.text(label), findsWidgets);
      }
      await _tap(tester, find.text('Journey').last);
      expect(find.byType(JourneyPage), findsOneWidget);
      await _tap(tester, find.text('Messages').last);
      expect(find.byType(ConversationsPage), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Messages' &&
              w.properties.selected == true &&
              w.properties.button == true,
        ),
        findsOneWidget,
      );
    });
  });
}
