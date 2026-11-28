// Article comments: a deleted comment, and a comment from a deleted or
// deactivated account, keep the normal comment layout (photo, name line,
// text) with placeholder names. The data shape matches get_article_comments
// in 20261128020000_article_comment_authors.sql.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maak_app/frontend/patient/article_comments.dart';

import 'helpers/screen_harness.dart';

const _peer = '00000000-0000-0000-0000-000000000002';

Map<String, dynamic> _row(
  String id, {
  String? body = 'Thanks for sharing!',
  String? name = 'Vera Volunteer',
  String? role = 'volunteer',
  String? userId = _peer,
  bool deleted = false,
  String status = 'active',
  String? createdAt,
}) => {
  'id': id,
  'article_id': 'art-1',
  'user_id': deleted || status != 'active' ? null : userId,
  'parent_id': null,
  'reply_to_id': null,
  'reply_to_name': null,
  'body': deleted ? '' : body,
  'created_at': createdAt ?? '2026-01-05T10:00:00Z',
  'author_name': deleted
      ? null
      : switch (status) {
          'deleted' => '[deleted account]',
          'deactivated' => '[deactivated account]',
          _ => name,
        },
  'author_role': deleted || status != 'active' ? null : role,
  'is_mine': false,
  'is_deleted': deleted,
  'author_status': status,
};

Future<void> _open(WidgetTester tester, List<Map<String, dynamic>> rows) async {
  await signIn('Sara Seeker');
  fakeBackend = backendFrom({'/rpc/get_article_comments': rows});
  await pumpScreen(
    tester,
    const Scaffold(
      body: SingleChildScrollView(
        child: ArticleCommentsSection(articleId: 'art-1'),
      ),
    ),
  );
}

/// The whole comment tile (photo + name line + text) holding [text].
Finder _tile(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(Row)).first;

void main() {
  setUpAll(setUpScreenHarness);

  testScreen('a deleted comment keeps the name line: "[deleted]"', (
    tester,
  ) async {
    await _open(tester, [
      _row('c1', name: 'Vera Volunteer'),
      _row('c2', deleted: true),
    ]);
    expect(find.text('[deleted]'), findsOneWidget);
    expect(find.text('This message was deleted by the user.'), findsOneWidget);
    // Same layout as a normal comment: about the same height, not a slim
    // one-line placeholder.
    final normal = tester.getSize(_tile('Vera Volunteer')).height;
    final deleted = tester.getSize(_tile('[deleted]')).height;
    expect(deleted, greaterThanOrEqualTo(normal - 6));
    // Nothing to reply to or delete on a deleted comment.
    expect(find.byTooltip('Comment options'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testScreen('deleted or deactivated accounts: the text stays, the name '
      'is a placeholder and opens no profile', (tester) async {
    await _open(tester, [
      _row('c1', body: 'Walking after meals helped me.', status: 'deleted'),
      _row('c2', body: 'Drink water before exercise.', status: 'deactivated'),
    ]);
    expect(find.text('[deleted account]'), findsOneWidget);
    expect(find.text('[deactivated account]'), findsOneWidget);
    expect(find.text('Walking after meals helped me.'), findsOneWidget);
    expect(find.text('Drink water before exercise.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp("profile")), findsNothing);
    expect(
      find.byKey(const ValueKey('comment_placeholder_photo')),
      findsNWidgets(2),
    );
    // No role badge for a removed account.
    expect(find.text('Volunteer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testScreen('the time stays on the name line, even for long names', (
    tester,
  ) async {
    // Three hours ago: the label is "3 h" (no "ago").
    final threeHours = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 3, minutes: 5))
        .toIso8601String();
    await _open(tester, [
      _row('c1', status: 'deactivated', createdAt: threeHours),
      _row(
        'c2',
        name: 'Abdulrahman Mohammed Abdullah Al-Qahtani Al-Shammari',
        createdAt: threeHours,
      ),
      _row('c3', name: 'Sara', createdAt: threeHours),
    ]);
    expect(find.textContaining('ago'), findsNothing);
    final time = find.text('3 h');
    expect(time, findsNWidgets(3));
    for (final name in [
      '[deactivated account]',
      'Abdulrahman Mohammed Abdullah Al-Qahtani Al-Shammari',
      'Sara',
    ]) {
      final nameRect = tester.getRect(find.text(name));
      final line = find.ancestor(
        of: find.text(name),
        matching: find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('comment_name_line_'),
        ),
      );
      final timeRect = tester.getRect(
        find.descendant(of: line, matching: time),
      );
      // Same line: the time's vertical centre is within the name's line.
      expect(timeRect.center.dy, closeTo(nameRect.center.dy, 4), reason: name);
      // And it fits on screen.
      expect(timeRect.right, lessThanOrEqualTo(390), reason: name);
    }
    expect(tester.takeException(), isNull);
  });

  test('time labels have no "ago"', () {
    String at(Duration d) =>
        commentTimeAgo(DateTime.now().subtract(d).toUtc().toIso8601String());
    expect(at(Duration.zero), 'Just now');
    expect(at(const Duration(minutes: 5, seconds: 5)), '5 min');
    expect(at(const Duration(hours: 3, minutes: 5)), '3 h');
    expect(at(const Duration(days: 1, hours: 1)), '1 day');
    expect(at(const Duration(days: 2, hours: 1)), '2 days');
    expect(at(const Duration(days: 7, hours: 1)), '1 week');
    expect(at(const Duration(days: 13)), '1 week');
    expect(at(const Duration(days: 14, hours: 1)), '2 weeks');
    expect(at(const Duration(days: 60)), '8 weeks');
  });
}
