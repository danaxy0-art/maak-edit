import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Reader-facing access to the Health Library.
/// Does not modify existing account, chat, or resource services.
class HealthLibraryService {
  HealthLibraryService._();

  static SupabaseClient get _db => SupabaseService.client;
  static String get _userId => SupabaseService.userId;

  /// Returns the categories used by published Health Library articles.
  static Future<List<Map<String, dynamic>>> getIllnessTypes() async {
    final rows = await _db.from('illness_types').select('id,name').order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Loads published articles and their like counts and current-user state.
  /// Search is case-insensitive across article titles and summaries.
  /// [collection] accepts 'all', 'liked', or 'saved'.
  /// [sort] accepts 'newest', 'oldest', or 'popular'.
  static Future<List<Map<String, dynamic>>> getArticles({
    String search = '',
    String? illnessTypeId,
    String collection = 'all',
    String sort = 'newest',
  }) async {
    if (!{'all', 'liked', 'saved'}.contains(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    if (!{'newest', 'oldest', 'popular'}.contains(sort)) {
      throw ArgumentError.value(sort, 'sort');
    }

    var query = _db.from('articles').select(
      'id,title,summary,content,illness_type_id,source_name,source_url,'
      'image_url,status,published_at,created_at,updated_at,'
      'illness_types(name)',
    ).eq('status', 'published');
    if (illnessTypeId != null && illnessTypeId.isNotEmpty) {
      query = query.eq('illness_type_id', illnessTypeId);
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
    return await _db.from('articles').select(
      'id,title,summary,content,illness_type_id,source_name,source_url,'
      'image_url,published_at,created_at,illness_types(name)',
    ).eq('id', articleId).eq('status', 'published').maybeSingle();
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
}
