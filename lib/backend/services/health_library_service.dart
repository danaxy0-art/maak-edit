import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Reader-facing access to the Health Library.
/// Does not modify existing account, chat, or resource services.
class HealthLibraryService {
  HealthLibraryService._();

  static SupabaseClient get _db => SupabaseService.client;
  static String get _userId => SupabaseService.userId;

  /// The health conditions stored in the database (Admin > Conditions), for
  /// filtering articles. "Other" is not a topic, so it is left out.
  static Future<List<Map<String, dynamic>>> getConditions() async {
    final rows = await SupabaseService.getConditions();
    return rows.where((c) => c['is_other'] != true).toList();
  }

  // Article columns read by the library. `condition` is the article's health
  // condition from chronic_conditions ({name}), or null for general articles.
  static const _articleColumns =
      'id,title,summary,content,condition_id,source_name,source_url,'
      'image_url,status,published_at,created_at,updated_at,'
      'condition:chronic_conditions(name)';

  /// Loads published articles and their like counts and current-user state.
  /// Search is case-insensitive across article titles and summaries.
  /// [collection] accepts 'all', 'liked', or 'saved'.
  /// [sort] accepts 'newest', 'oldest', or 'popular'.
  static Future<List<Map<String, dynamic>>> getArticles({
    String search = '',
    String? conditionId,
    String collection = 'all',
    String sort = 'newest',
  }) async {
    if (!{'all', 'liked', 'saved'}.contains(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    if (!{'newest', 'oldest', 'popular'}.contains(sort)) {
      throw ArgumentError.value(sort, 'sort');
    }

    var query =
        _db.from('articles').select(_articleColumns).eq('status', 'published');
    if (conditionId != null && conditionId.isNotEmpty) {
      query = query.eq('condition_id', conditionId);
    }
    // Fetch published rows before filtering locally, so user search strings
    // cannot become PostgREST filter syntax.
    final rows = List<Map<String, dynamic>>.from(await query);
    final ids = rows.map((row) => row['id'] as String).toList();
    if (ids.isEmpty) return [];

    final likes = List<Map<String, dynamic>>.from(
      await _db.from('article_likes').select('article_id,user_id').inFilter('article_id', ids),
    );
    final saves = List<Map<String, dynamic>>.from(
      await _db.from('saved_articles').select('article_id').eq('user_id', _userId).inFilter('article_id', ids),
    );

    final counts = <String, int>{};
    // Aggregate counts are returned by a narrowly scoped database function.
    // RLS intentionally hides other users' individual like rows.
    final publicCounts = List<dynamic>.from(
      await _db.rpc('health_article_like_counts'),
    );
    for (final item in publicCounts) {
      final countRow = Map<String, dynamic>.from(item as Map);
      counts[countRow['article_id'] as String] =
          (countRow['like_count'] as num).toInt();
    }
    // Comment counts are optional: an older database without the comments
    // migration still shows the library.
    final commentCounts = <String, int>{};
    try {
      final rows = List<dynamic>.from(
        await _db.rpc('health_article_comment_counts'),
      );
      for (final item in rows) {
        final row = Map<String, dynamic>.from(item as Map);
        commentCounts[row['article_id'] as String] =
            (row['comment_count'] as num).toInt();
      }
    } catch (_) {}
    final liked = <String>{};
    for (final like in likes) {
      final id = like['article_id'] as String;
      if (like['user_id'] == _userId) liked.add(id);
    }
    final saved = saves.map((row) => row['article_id'] as String).toSet();
    final needle = search.trim().toLowerCase();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = row['id'] as String;
      if (collection == 'liked' && !liked.contains(id)) continue;
      if (collection == 'saved' && !saved.contains(id)) continue;
      final title = (row['title'] as String? ?? '').toLowerCase();
      final summary = (row['summary'] as String? ?? '').toLowerCase();
      if (needle.isNotEmpty && !title.contains(needle) && !summary.contains(needle)) continue;
      result.add({
        ...row,
        'like_count': counts[id] ?? 0,
        'comment_count': commentCounts[id] ?? 0,
        'is_liked': liked.contains(id),
        'is_saved': saved.contains(id),
      });
    }
    if (sort == 'popular') {
      result.sort((a, b) {
        final difference = (b['like_count'] as int).compareTo(a['like_count'] as int);
        return difference != 0 ? difference : _date(b).compareTo(_date(a));
      });
    } else {
      result.sort((a, b) => sort == 'oldest'
          ? _date(a).compareTo(_date(b))
          : _date(b).compareTo(_date(a)));
    }
    return result;
  }

  static DateTime _date(Map<String, dynamic> row) =>
      DateTime.tryParse((row['published_at'] ?? row['created_at'] ?? '').toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns full content for one published article.
  static Future<Map<String, dynamic>?> getArticle(String articleId) async {
    return await _db
        .from('articles')
        .select(_articleColumns)
        .eq('id', articleId)
        .eq('status', 'published')
        .maybeSingle();
  }

  /// Like and save state of one article for the article page:
  /// {is_liked, is_saved, like_count}.
  static Future<Map<String, dynamic>> getArticleState(String articleId) async {
    final like = await _db
        .from('article_likes')
        .select('article_id')
        .eq('user_id', _userId)
        .eq('article_id', articleId)
        .maybeSingle();
    final save = await _db
        .from('saved_articles')
        .select('article_id')
        .eq('user_id', _userId)
        .eq('article_id', articleId)
        .maybeSingle();
    var count = 0;
    for (final item in List<dynamic>.from(await _db.rpc('health_article_like_counts'))) {
      final row = Map<String, dynamic>.from(item as Map);
      if (row['article_id'] == articleId) count = (row['like_count'] as num).toInt();
    }
    return {'is_liked': like != null, 'is_saved': save != null, 'like_count': count};
  }

  /// Adds or removes the current user's like. The database primary key
  /// prevents duplicate likes, including across multiple devices.
  static Future<bool> setLiked(String articleId, {required bool liked}) async {
    if (liked) {
      await _db.from('article_likes').upsert(
        {'user_id': _userId, 'article_id': articleId},
        onConflict: 'user_id,article_id',
        ignoreDuplicates: true,
      );
    } else {
      await _db.from('article_likes').delete().eq('user_id', _userId).eq('article_id', articleId);
    }
    return liked;
  }

  /// Adds or removes an article from the current user's saved collection.
  static Future<bool> setSaved(String articleId, {required bool saved}) async {
    if (saved) {
      await _db.from('saved_articles').upsert(
        {'user_id': _userId, 'article_id': articleId},
        onConflict: 'user_id,article_id',
        ignoreDuplicates: true,
      );
    } else {
      await _db.from('saved_articles').delete().eq('user_id', _userId).eq('article_id', articleId);
    }
    return saved;
  }

  // --- Comments (20261126000000_article_management_comments.sql) -----------

  /// Longest comment or reply accepted by the database.
  static const maxCommentLength = 1000;

  /// All comments of one article, oldest first, with author name and role.
  /// Each row: id, article_id, user_id, parent_id (top-level comment of the
  /// thread, null for top-level), reply_to_id, reply_to_name, body,
  /// created_at, author_name, author_role, is_mine.
  static Future<List<Map<String, dynamic>>> getComments(String articleId) async {
    final rows = await _db.rpc(
      'get_article_comments',
      params: {'p_article_id': articleId},
    );
    return List<dynamic>.from(rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Adds a comment, or a reply to [replyToId]. The author of the comment
  /// being answered is notified by the database. Returns the new comment id.
  static Future<String> addComment(
    String articleId,
    String body, {
    String? replyToId,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Write a comment first.');
    // runes = code points, the same unit as the database's char_length.
    if (text.runes.length > maxCommentLength) {
      throw ArgumentError(
        'Keep your comment under $maxCommentLength characters.',
      );
    }
    final id = await _db.rpc('add_article_comment', params: {
      'p_article_id': articleId,
      'p_body': text,
      'p_reply_to': replyToId,
    });
    return id as String;
  }

  /// Deletes the caller's own comment (admins: any comment). Deleting a
  /// top-level comment also removes its replies.
  static Future<void> deleteComment(String commentId) async {
    await _db.rpc(
      'delete_article_comment',
      params: {'p_comment_id': commentId},
    );
  }
}
