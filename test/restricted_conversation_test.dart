// Participant side of an administrator-restricted conversation
// (support_requests.restricted_at, set by admin_restrict_conversation via
// admin_end_reported_conversation), and restricted-notification navigation.
// Supabase is a fake backend (test/helpers/screen_harness.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maak_app/frontend/redesign/chat_media.dart';
import 'package:maak_app/frontend/redesign/notifications.dart';
import 'package:maak_app/frontend/redesign/shell.dart';
import 'package:maak_app/frontend/redesign/support.dart';

import 'helpers/screen_harness.dart';

const me = '00000000-0000-0000-0000-000000000001'; // signIn() user
const peer = '00000000-0000-0000-0000-000000000002';
const req = '00000000-0000-0000-0000-0000000000c1';
const reason = 'Repeated insults toward a help seeker.';

/// Server state the fake backend returns for the conversation.
class Chat {
  bool restricted = false, endedByMe = false, iAmVolunteer = false;
  final calls = <String>[];
  Map<String, dynamic> row() => {
    'id': req,
    'seeker_id': iAmVolunteer ? peer : me,
    'volunteer_id': iAmVolunteer ? me : peer,
    'status': 'accepted',
    'created_at': '2026-11-01T10:00:00Z',
    'ended_at': endedByMe ? '2026-11-06T07:00:00Z' : null,
    'ended_by': endedByMe ? me : null,
    'restricted_at': restricted ? '2026-11-06T08:00:00Z' : null,
    'restricted_by': null,
    'restriction_reason': restricted ? reason : null,
  };
}

Map<String, dynamic> note(String id, String kind, {String? reference}) => {
  'id': '00000000-0000-0000-0000-0000000000$id',
  'user_id': me,
  'title': 'Title $kind',
  'body': 'Body $kind',
  'kind': kind,
  'reference_id': reference,
  'is_read': false,
  'created_at': '2026-11-06T08:00:00Z',
};

FakeBackend backend(Chat chat, {String role = 'help_seeker'}) => (request) {
  final p = request.url.path;
  chat.calls.add('${request.method} ${p.split('/').last}');
  final object = (request.headers['Accept'] ?? '').contains('vnd.pgrst.object');
  Future<http.Response> ok(Object? b) =>
      Future.value(jsonResponse(request, b ?? const []));
  if (p.endsWith('/support_requests')) {
    return ok(object ? chat.row() : [chat.row()]);
  }
  if (p.endsWith('/profiles')) {
    final profile = {'id': me, 'role': role, 'full_name': 'Layla'};
    return ok(object ? profile : [profile]);
  }
  if (p.endsWith('my_maak_chat_messages')) {
    return ok([
      {
        'id': 'm1',
        'request_id': req,
        'sender_id': peer,
        'body': 'Hello, how are you feeling today?',
        'message_type': 'text',
        'created_at': '2026-11-05T10:00:00Z',
        'deleted_at': null,
        'read_at': null,
      },
    ]);
  }
  if (p.endsWith('end_maak_chat') || p.endsWith('request_maak_chat_reopen')) {
    return ok(null);
  }
  return null;
};

Finder conversation(String id) =>
    find.byWidgetPredicate((w) => w is ConversationPage && w.requestId == id);
bool menuEnabled(WidgetTester t) => t
    .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
    .enabled;

void main() {
  setUpAll(() async {
    await setUpScreenHarness();
    // The chat's voice recorder and player plugins have no native side in
    // widget tests; answer their platform channels with no-ops.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'com.llfbandit.record/messages',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    // Each player also opens its own event channel, named after its id.
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        final id = (call.arguments as Map?)?['playerId'];
        if (call.method == 'create' && id != null) {
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        return null;
      },
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  Future<Chat> open(
    WidgetTester t, {
    bool restricted = false,
    bool endedByMe = false,
    bool volunteer = false,
    Stream<List<Map<String, dynamic>>>? notifications,
  }) async {
    await t.runAsync(() => signIn('Layla'));
    final chat = Chat()
      ..restricted = restricted
      ..endedByMe = endedByMe
      ..iAmVolunteer = volunteer;
    fakeBackend = backend(chat, role: volunteer ? 'volunteer' : 'help_seeker');
    await pumpScreen(
      t,
      ConversationPage(
        requestId: req,
        name: 'Omar',
        notifications: notifications ?? const Stream.empty(),
      ),
    );
    return chat;
  }

  void expectRestrictedUi(WidgetTester t) {
    expect(
      find.byKey(const ValueKey('admin_restricted_banner')),
      findsOneWidget,
    );
    expect(find.text('Ended by an administrator'), findsOneWidget);
    expect(find.text('Reason: $reason'), findsOneWidget);
    expect(find.text('Conversation ended'), findsNothing);
    expect(find.text('Hello, how are you feeling today?'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Write a message...'), findsNothing);
    expect(find.byType(ChatMediaComposer), findsNothing);
    expect(find.byTooltip('Send message'), findsNothing);
    expect(
      find.text(
        'An administrator ended this chat — you can no longer send messages.',
      ),
      findsOneWidget,
    );
    expect(find.text('Request to reopen chat'), findsNothing);
    expect(menuEnabled(t), isFalse, reason: 'End chat menu disabled');
  }

  group('Administrator-restricted conversation', () {
    for (final volunteer in [false, true]) {
      final role = volunteer ? 'volunteer' : 'help seeker';
      testScreen('$role sees the banner, reason and history only', (t) async {
        await open(t, restricted: true, volunteer: volunteer);
        expectRestrictedUi(t);
      });
    }

    testScreen('reactions and deleting are not offered for messages', (
      t,
    ) async {
      await open(t, restricted: true);
      await t.tap(find.byTooltip('Message options · Delete'));
      await settle(t);
      expect(find.text('Message options'), findsOneWidget);
      expect(find.text('React'), findsNothing);
      expect(find.text('Delete for me'), findsNothing);
      expect(find.text('Delete for everyone'), findsNothing);
      // Reporting the other person's message stays available.
      expect(find.text('Report message'), findsOneWidget);
    });

    testScreen('a participant-ended chat still offers Delete for me', (
      t,
    ) async {
      await open(t, endedByMe: true);
      await t.tap(find.byTooltip('Message options · Delete'));
      await settle(t);
      expect(find.text('Delete for me'), findsOneWidget);
    });

    testScreen('a chat I ended is shown as admin-restricted, no reopen', (
      t,
    ) async {
      await open(t, restricted: true, endedByMe: true);
      expectRestrictedUi(t);
      expect(
        find.text(
          'Only the person who ended the conversation can request to reopen it.',
        ),
        findsNothing,
      );
    });

    testScreen('a restriction made while the chat is open is shown', (t) async {
      final notes = StreamController<List<Map<String, dynamic>>>.broadcast();
      addTearDown(notes.close);
      final chat = await open(t, notifications: notes.stream);
      notes.add([note('a1', 'message', reference: req)]); // baseline
      await settle(t);
      expect(find.widgetWithText(TextField, 'Write a message...'), findsOne);
      // The admin ends it; the server sends a 'restricted' notification.
      chat.restricted = true;
      notes.add([
        note('a2', 'restricted', reference: req),
        note('a1', 'message', reference: req),
      ]);
      await settle(t);
      expectRestrictedUi(t);
    });

    testScreen('a restriction for another conversation is ignored', (t) async {
      final notes = StreamController<List<Map<String, dynamic>>>.broadcast();
      addTearDown(notes.close);
      final chat = await open(t, notifications: notes.stream);
      notes.add([]);
      await settle(t);
      final reloads = chat.calls.where((c) => c == 'GET support_requests');
      final before = reloads.length;
      notes.add([note('b1', 'restricted', reference: 'other-request')]);
      await settle(t);
      expect(
        chat.calls.where((c) => c == 'GET support_requests').length,
        before,
      );
      expect(find.widgetWithText(TextField, 'Write a message...'), findsOne);
    });
  });

  group('Participant End Chat and Reopen are unchanged', () {
    testScreen('an active chat keeps the composer and End chat', (t) async {
      await open(t);
      expect(find.widgetWithText(TextField, 'Write a message...'), findsOne);
      expect(find.byType(ChatMediaComposer), findsOneWidget);
      expect(find.text('Ended by an administrator'), findsNothing);
      expect(menuEnabled(t), isTrue);
    });

    testScreen('End chat ends it and offers a reopen request', (t) async {
      final chat = await open(t);
      await t.tap(find.byTooltip('Conversation options'));
      await settle(t);
      await t.tap(find.text('End chat'));
      await settle(t);
      expect(find.text('End conversation?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'End chat'));
      await settle(t);
      expect(chat.calls, contains('POST end_maak_chat'));
      expect(find.text('Conversation ended'), findsOneWidget);
      expect(find.text('Ended by an administrator'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Write a message...'),
        findsNothing,
      );
      expect(find.text('Request to reopen chat'), findsOneWidget);
    });

    testScreen('the person who ended it is offered a reopen request', (
      t,
    ) async {
      await open(t, endedByMe: true);
      expect(find.text('Conversation ended'), findsOneWidget);
      expect(
        find.text('Chat ended — you can no longer send messages.'),
        findsOne,
      );
      await t.tap(find.text('Request to reopen chat'));
      await settle(t);
      expect(find.text('Request to reopen chat?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send request'), findsOne);
    });

    // Regression: _refreshReopenRequests() used to return a Future from its
    // setState callback, which threw in debug builds after a reopen request.
    testScreen('sending a reopen request completes without errors', (t) async {
      final chat = await open(t, endedByMe: true);
      await t.tap(find.text('Request to reopen chat'));
      await settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Send request'));
      await settle(t);
      expect(chat.calls, contains('POST request_maak_chat_reopen'));
      // Let the 5 s reopen refresh run too; it uses the same setState.
      await t.pump(const Duration(seconds: 6));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('Conversation ended'), findsOneWidget);
    });
  });

  group('Notifications page navigation', () {
    Future<Chat> openList(
      WidgetTester t,
      List<Map<String, dynamic>> notes, {
      bool volunteer = false,
    }) async {
      await t.runAsync(() => signIn('Layla'));
      final chat = Chat()..iAmVolunteer = volunteer;
      fakeBackend = backend(
        chat,
        role: volunteer ? 'volunteer' : 'help_seeker',
      );
      // A fresh tree, so a conversation pushed earlier in the test is gone.
      await t.pumpWidget(const SizedBox());
      await pumpScreen(t, NotificationsPage(stream: Stream.value(notes)));
      return chat;
    }

    for (final volunteer in [false, true]) {
      final role = volunteer ? 'volunteer' : 'help seeker';
      testScreen('$role: restricted opens the conversation, marked read', (
        t,
      ) async {
        final chat = await openList(t, [
          note('c1', 'restricted', reference: req),
        ], volunteer: volunteer);
        expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOne);
        await t.tap(find.text('Title restricted'));
        await settle(t);
        expect(conversation(req), findsOneWidget);
        expect(chat.calls, contains('PATCH notifications'));
      });
    }

    testScreen('message and chat_reopen still open the conversation', (
      t,
    ) async {
      for (final kind in ['message', 'chat_reopen']) {
        await openList(t, [note('d1', kind, reference: req)]);
        await t.tap(find.text('Title $kind'));
        await settle(t);
        expect(conversation(req), findsOneWidget, reason: kind);
      }
    });

    testScreen('request still opens Journey (seeker) / Requests (volunteer)', (
      t,
    ) async {
      await openList(t, [note('e1', 'request', reference: req)]);
      await t.tap(find.text('Title request'));
      await settle(t);
      expect(find.byType(JourneyPage), findsOneWidget);
      await openList(t, [
        note('e2', 'request', reference: req),
      ], volunteer: true);
      await t.tap(find.text('Title request'));
      await settle(t);
      expect(find.byType(RequestsPage), findsOneWidget);
    });

    testScreen('other kinds still only mark read', (t) async {
      final chat = await openList(t, [note('f1', 'account')]);
      await t.tap(find.text('Title account'));
      await settle(t);
      expect(find.byType(ConversationPage), findsNothing);
      expect(chat.calls, contains('PATCH notifications'));
    });
  });

  group('Pop-up banner navigation (AppShell)', () {
    for (final volunteer in [false, true]) {
      final role = volunteer ? 'volunteer' : 'help_seeker';
      testScreen('$role: tapping a restricted banner opens the chat', (
        t,
      ) async {
        await t.runAsync(() => signIn('Layla'));
        final chat = Chat()..iAmVolunteer = volunteer;
        fakeBackend = backend(chat, role: role);
        final notes = StreamController<List<Map<String, dynamic>>>();
        addTearDown(notes.close);
        await pumpScreen(t, AppShell(role: role, notifications: notes.stream));
        notes.add([]); // baseline snapshot
        await settle(t);
        notes.add([note('g1', 'restricted', reference: req)]);
        await settle(t);
        await t.tap(find.text('Title restricted'));
        await settle(t);
        expect(conversation(req), findsOneWidget);
        expect(chat.calls, contains('PATCH notifications'));
      });
    }

    testScreen('message banner still opens the chat; request opens Requests', (
      t,
    ) async {
      await t.runAsync(() => signIn('Layla'));
      final chat = Chat()..iAmVolunteer = true;
      fakeBackend = backend(chat, role: 'volunteer');
      final notes = StreamController<List<Map<String, dynamic>>>();
      addTearDown(notes.close);
      await pumpScreen(
        t,
        AppShell(role: 'volunteer', notifications: notes.stream),
      );
      notes.add([]);
      await settle(t);
      notes.add([note('h1', 'message', reference: req)]);
      await settle(t);
      await t.tap(find.text('Title message'));
      await settle(t);
      expect(conversation(req), findsOneWidget);
      await t.pageBack();
      await settle(t);
      notes.add([
        note('h2', 'request', reference: req),
        note('h1', 'message', reference: req),
      ]);
      await settle(t);
      await t.tap(find.text('Title request'));
      await settle(t);
      expect(find.byType(RequestsPage), findsWidgets);
    });
  });
}
