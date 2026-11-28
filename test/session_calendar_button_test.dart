// Sprint 4 US5: "Add to calendar" inside Razan's real SessionsPage
// (lib/frontend/redesign/sessions.dart). MOCKED: the session list comes from
// the fake Supabase backend and the calendar is a fake; no device calendar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/backend/services/device_session_calendar.dart';
import 'package:maak_app/backend/services/session_calendar.dart';
import 'package:maak_app/frontend/redesign/session_calendar_button.dart';
import 'package:maak_app/frontend/redesign/sessions.dart';

import 'helpers/screen_harness.dart';
import 'session_calendar_test.dart' show FakeCalendar, MemoryStore, tokens;

String _at(int days, int hour) => DateTime.now()
    .add(Duration(days: days))
    .copyWith(hour: hour, minute: 0, second: 0, millisecond: 0)
    .toUtc()
    .toIso8601String();

Map<String, dynamic> _row(
  String id,
  String status, {
  String? display,
  bool volunteer = false,
  int days = 3,
  String slot = 'slot-1',
}) => {
  'id': id,
  'slot_id': '$slot-$id',
  'status': status,
  'display_status': display ?? status,
  'starts_at': _at(days, 18),
  'ends_at': _at(days, 19),
  'volunteer_id': 'vol-1',
  'seeker_id': 'seek-1',
  'is_volunteer': volunteer,
  'contact_name': 'Layla',
  'reschedule_count': 0,
  'canceled_by_me': false,
};

final _button = find.byKey(const ValueKey('session_calendar_button'));

void main() {
  setUpAll(setUpScreenHarness);
  late FakeCalendar calendar;
  late MemoryStore store;
  setUp(() {
    calendar = FakeCalendar();
    store = MemoryStore();
    AppSessionCalendar.instance = SessionCalendar(
      gateway: calendar,
      store: store,
      newToken: tokens(),
    );
  });
  tearDown(() => AppSessionCalendar.instance = null);

  Future<void> open(
    WidgetTester tester,
    List<Map<String, dynamic>> rows, {
    String role = 'help_seeker',
  }) async {
    fakeBackend = backendFrom({'/rpc/my_maak_sessions': rows});
    await pumpScreen(tester, SessionsPage(role: role));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  testScreen('only confirmed upcoming sessions get the action', (tester) async {
    await open(tester, [
      _row('a', 'accepted'),
      _row('b', 'pending'),
      _row('c', 'canceled'),
      _row('d', 'rejected'),
      _row('e', 'accepted', display: 'completed', days: -2),
    ]);
    expect(_button, findsOneWidget);
    expect(find.text('Add to calendar'), findsOneWidget);
  });

  testScreen('the volunteer gets it too', (tester) async {
    await open(tester, [
      _row('a', 'accepted', volunteer: true),
    ], role: 'volunteer');
    expect(find.text('Add to calendar'), findsOneWidget);
  });

  testScreen('add, then "In your calendar"; a second tap adds nothing', (
    tester,
  ) async {
    await open(tester, [_row('a', 'accepted')]);
    await tap(tester, find.text('Add to calendar'));
    expect(find.text('Added to your calendar.'), findsOneWidget);
    expect(find.text('In your calendar'), findsOneWidget);
    await tap(tester, find.text('In your calendar'));
    expect(
      find.text('This session is already in your calendar.'),
      findsOneWidget,
    );
    expect(calendar.creates, 1);
  });

  testScreen('busy while saving; repeated taps do not create duplicates', (
    tester,
  ) async {
    calendar.holdCreate = Completer<void>();
    await open(tester, [_row('a', 'accepted')]);
    await tester.ensureVisible(_button);
    await tester.tap(_button);
    await tester.pump();
    expect(
      find.descendant(
        of: _button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Saving to calendar')), findsOneWidget);
    await tester.tap(_button, warnIfMissed: false);
    await tester.pump();
    calendar.holdCreate!.complete();
    await settle(tester);
    expect(calendar.creates, 1);
    expect(find.text('In your calendar'), findsOneWidget);
  });

  testScreen('denied: explains Settings, never says added', (tester) async {
    calendar.access = CalendarAccess.denied;
    await open(tester, [_row('a', 'accepted')]);
    await tap(tester, find.text('Add to calendar'));
    expect(
      find.textContaining('Allow calendar access in Settings'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);
    expect(find.text('Added to your calendar.'), findsNothing);
    expect(find.text('Add to calendar'), findsOneWidget);
  });

  testScreen('restricted and no calendar account: plain explanations', (
    tester,
  ) async {
    calendar.access = CalendarAccess.restricted;
    await open(tester, [_row('a', 'accepted')]);
    await tap(tester, find.text('Add to calendar'));
    expect(
      find.text('Calendar access is restricted on this phone.'),
      findsOneWidget,
    );
    calendar.access = CalendarAccess.unavailable;
    await tap(tester, find.text('Add to calendar'));
    expect(
      find.text('Add a calendar account to this phone to save sessions there.'),
      findsOneWidget,
    );
    expect(store.saved, isEmpty);
  });

  testScreen('a calendar failure shows an error, not success', (tester) async {
    calendar.createError = Exception('provider crashed');
    await open(tester, [_row('a', 'accepted')]);
    await tap(tester, find.text('Add to calendar'));
    expect(find.text('Please check this'), findsOneWidget);
    expect(find.text('Added to your calendar.'), findsNothing);
  });

  testScreen('rescheduled after adding: "Update calendar", then updated', (
    tester,
  ) async {
    final row = _row('a', 'accepted');
    final old = SessionCalendarEvent.fromSession({
      ...row,
      'slot_id': 'old-slot',
      'starts_at': _at(2, 10),
      'ends_at': _at(2, 11),
    })!;
    calendar.events['evt-1'] = old;
    store.saved['a'] = SavedSessionEvent.of(old, eventId: 'evt-1');
    await open(tester, [row]);
    expect(find.text('Update calendar'), findsOneWidget);
    expect(find.textContaining('still shows the old time'), findsOneWidget);
    await tap(tester, find.text('Update calendar'));
    expect(find.text('Your calendar now shows the new time.'), findsOneWidget);
    expect(find.text('In your calendar'), findsOneWidget);
    expect(calendar.updates, 1);
    expect(calendar.creates, 0);
  });

  group('refresh race', () {
    // Each read waits until the test releases it, so answers can be
    // delivered out of order.
    late _HeldStore held;
    late SessionCalendar slow;
    setUp(() {
      held = _HeldStore();
      slow = SessionCalendar(
        gateway: calendar,
        store: held,
        newToken: tokens(),
      );
    });

    // The card stays mounted and receives a new row, as when the session
    // list reloads (this is what reaches didUpdateWidget).
    late ValueNotifier<Map<String, dynamic>> row;
    Future<void> show(WidgetTester tester, Map<String, dynamic> first) {
      row = ValueNotifier(first);
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: row,
              builder: (_, value, _) =>
                  SessionCalendarButton(session: value, calendar: slow),
            ),
          ),
        ),
      );
    }

    testWidgets('an older, slower answer never overwrites a newer one', (
      tester,
    ) async {
      final before = _row('a', 'accepted', slot: 'old');
      final after = {
        ...before,
        'slot_id': 'new-a',
        'starts_at': _at(4, 18),
        'ends_at': _at(4, 19),
      };
      // Saved at the old time: old row = "In your calendar",
      // rescheduled row = "Update calendar".
      held.saved['a'] = SavedSessionEvent.of(
        SessionCalendarEvent.fromSession(before)!,
        eventId: 'evt-1',
      );
      calendar.events['evt-1'] = SessionCalendarEvent.fromSession(before)!;
      await show(tester, before); // refresh 1 (old row) waits
      row.value = after; // the list reloads: refresh 2 (new row) waits
      await tester.pump();
      expect(held.waiting, 2);
      held.release(1); // the newer answer first
      // One frame for the answer, one to draw it.
      await tester.pump();
      await tester.pump();
      expect(find.text('Update calendar'), findsOneWidget);
      held.release(0); // the stale answer arrives late
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Update calendar'),
        findsOneWidget,
        reason: 'stale "In your calendar" ignored',
      );
      expect(find.text('In your calendar'), findsNothing);
    });

    testWidgets('an answer arriving after the card is gone is dropped', (
      tester,
    ) async {
      await show(tester, _row('a', 'accepted'));
      expect(held.waiting, 1);
      await tester.pumpWidget(const SizedBox());
      held.release(0);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('only the end time changing still refreshes the label', (
      tester,
    ) async {
      final first = _row('a', 'accepted');
      await show(tester, first);
      held.release(0);
      await tester.pump();
      final reads = held.reads;
      row.value = {...first, 'ends_at': _at(3, 20)};
      await tester.pump();
      expect(held.reads, reads + 1, reason: 'a new refresh for the new end');
      held.releaseLast();
      await tester.pump();
      row.value = {...row.value}; // same values: no extra refresh
      await tester.pump();
      expect(held.reads, reads + 1);
    });
  });

  testScreen('unsupported platform: no action, Razan\'s buttons unchanged', (
    tester,
  ) async {
    calendar.isSupported = false;
    await open(tester, [_row('a', 'accepted')]);
    expect(_button, findsNothing);
    expect(find.text('Reschedule'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(calendar.accessRequests, 0);
  });
}

/// A [MemoryStore] whose reads wait until the test releases them.
class _HeldStore extends MemoryStore {
  final _gates = <Completer<void>?>[];
  int reads = 0;

  /// Reads still waiting.
  int get waiting => _gates.where((g) => g != null && !g.isCompleted).length;

  /// Lets read number [index] (0 = the first) finish.
  void release(int index) => _gates[index]!.complete();

  /// Lets the most recent read finish.
  void releaseLast() => _gates.last!.complete();

  @override
  Future<SavedSessionEvent?> read(String bookingId) async {
    reads++;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    return super.read(bookingId);
  }
}
