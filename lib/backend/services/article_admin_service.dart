import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Admin-only Health Library management. Every call goes through an RPC in
/// 20261126000000_article_management_comments.sql that checks the caller is an
/// administrator; members get 'not_allowed'.
class ArticleAdminService {
  ArticleAdminService._();

  static SupabaseClient get _db => SupabaseService.client;

  static const statuses = ['draft', 'published'];

  // Limits shared with admin_save_article.
  static const titleMax = 200;
  static const summaryMax = 500;
  static const contentMax = 20000;
  static const sourceNameMax = 120;
  static const urlMax = 2000;

  /// Every article (drafts included), most recently changed first, with
  /// condition_name, like_count and comment_count.
  static Future<List<Map<String, dynamic>>> listArticles() async {
    final rows = await _db.rpc('admin_list_articles');
    return List<dynamic>.from(rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// The health conditions stored in the database (Admin > Conditions),
  /// inactive ones included so an article can keep its current tag.
  /// "Other" is left out: it is not a topic.
  static Future<List<Map<String, dynamic>>> getConditions() async {
    final rows = await SupabaseService.getConditions(activeOnly: false);
    return rows.where((c) => c['is_other'] != true).toList();
  }

  /// Creates ([id] null) or updates an article. Returns its id.
  static Future<String> saveArticle({
    String? id,
    required String title,
    required String summary,
    required String content,
    String? conditionId,
    String? sourceName,
    String? sourceUrl,
    String? imageUrl,
    required String status,
  }) async {
    if (!statuses.contains(status)) throw ArgumentError.value(status, 'status');
    final result = await _db.rpc('admin_save_article', params: {
      'p_id': id,
      'p_title': title.trim(),
      'p_summary': summary.trim(),
      'p_content': content.trim(),
      'p_condition_id': conditionId,
      'p_source_name': sourceName?.trim(),
      'p_source_url': sourceUrl?.trim(),
      'p_image_url': imageUrl?.trim(),
      'p_status': status,
    });
    return result as String;
  }

  /// Publishes an article ('published') or moves it to drafts ('draft')
  /// without changing anything else. Publishing needs a source.
  static Future<void> setStatus(String id, String status) async {
    if (!statuses.contains(status)) throw ArgumentError.value(status, 'status');
    await _db.rpc('admin_set_article_status', params: {'p_id': id, 'p_status': status});
  }

  /// Deletes an article together with its likes, saves and comments.
  static Future<void> deleteArticle(String id) async {
    await _db.rpc<void>('admin_delete_article', params: {'p_id': id});
  }

  /// Same check as the database: http(s) with a host that has a dot.
  static bool isValidUrl(String value, {bool httpsOnly = false}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) return false;
    if (value.contains(RegExp(r'\s'))) return false;
    return httpsOnly
        ? uri.scheme == 'https'
        : uri.scheme == 'https' || uri.scheme == 'http';
  }
}
