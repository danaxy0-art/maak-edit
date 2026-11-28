import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:maak_app/frontend/redesign/admin.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setUpScreenHarness);
  tearDownAll(() => Supabase.instance.dispose());

  const article = <String, dynamic>{
    'id': '00000000-0000-0000-0000-000000000010',
    'title': 'Delete this draft',
    'summary': 'A draft article used for deletion testing.',
    'status': 'draft',
    'comment_count': 0,
    'like_count': 0,
  };

  for (final status in [200, 204]) {
    testScreen('draft deletion succeeds with HTTP $status void response',
        (tester) async {
      var deleted = false;
      var deleteCalls = 0;
      fakeBackend = (request) async {
        if (request.url.path.endsWith('/admin_list_articles')) {
          return jsonResponse(request, deleted ? [] : [article]);
        }
        if (request.url.path.endsWith('/admin_delete_article')) {
          deleteCalls++;
          deleted = true;
          return http.Response(status == 200 ? 'null' : '', status,
              headers: {'content-type': 'application/json'}, request: request);
        }
        return jsonResponse(request, []);
      };
      await signIn('Admin');
      await pumpScreen(tester, const ArticlesAdminPage());
      await tester.tap(find.byTooltip('Delete article'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleteCalls, 1);
      expect(find.text('Delete this draft'), findsNothing);
      expect(find.text('Article deleted.'), findsOneWidget);
      expect(find.text('Please check this'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testScreen('RPC failure keeps the draft and does not report success',
      (tester) async {
    fakeBackend = (request) async {
      if (request.url.path.endsWith('/admin_list_articles')) {
        return jsonResponse(request, [article]);
      }
      if (request.url.path.endsWith('/admin_delete_article')) {
        return jsonResponse(request,
            {'message': 'not_allowed', 'code': 'P0001'}, status: 400);
      }
      return jsonResponse(request, []);
    };
    await signIn('Admin');
    await pumpScreen(tester, const ArticlesAdminPage());
    await tester.tap(find.byTooltip('Delete article'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this draft'), findsOneWidget);
    expect(find.text('Article deleted.'), findsNothing);
    expect(find.text('Please check this'), findsOneWidget);
  });
}
