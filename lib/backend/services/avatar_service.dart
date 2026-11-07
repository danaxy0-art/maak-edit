import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../chat/chat_media_policy.dart' show imageMime;
import 'supabase_service.dart';

/// Profile pictures, stored in the private "avatars" bucket
/// (supabase/migrations/20261107000000_profile_pictures.sql and
/// 20261107010000_shared_profile_pictures.sql).
class AvatarService {
  AvatarService._();

  static const bucket = 'avatars';
  static const maxBytes = 5 * 1024 * 1024;

  /// Bumped whenever the signed-in user adds, changes or removes their
  /// picture, so every visible avatar reloads at once.
  static final revision = ValueNotifier<int>(0);

  // Signed URLs, keyed by file path. A changed picture has a new path, so a
  // cached URL never shows an old picture.
  static final Map<String, ({String url, DateTime expires})> _signed = {};

  // Lookups requested during the same frame are sent as one request.
  static final Map<String, Completer<String?>> _waiting = {};
  static bool _flushScheduled = false;

  /// A displayable URL for [userId]'s picture, or null when they have none
  /// (or it can't be loaded): callers then show initials.
  static Future<String?> urlFor(String userId) {
    final pending = _waiting[userId];
    if (pending != null) return pending.future;
    final completer = Completer<String?>();
    _waiting[userId] = completer;
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  static Future<void> _flush() async {
    _flushScheduled = false;
    final batch = Map.of(_waiting);
    _waiting.clear();
    Map<String, String> paths = {};
    try {
      if (SupabaseService.currentUser != null) {
        final rows = await SupabaseService.client.rpc(
          'maak_avatar_paths',
          params: {'p_user_ids': batch.keys.toList()},
        );
        paths = {
          for (final r in (rows as List).cast<Map>())
            '${r['user_id']}': '${r['avatar_path']}',
        };
        await Future.wait(paths.values.toSet().map(_sign));
      }
    } catch (error) {
      // Not set up yet, offline, or signed out: everyone shows initials.
      // PGRST202 here means 20261107010000_shared_profile_pictures.sql isn't applied.
      debugPrint('Profile pictures unavailable: $error');
      paths = {};
    }
    for (final entry in batch.entries) {
      final path = paths[entry.key];
      entry.value.complete(path == null ? null : _signed[path]?.url);
    }
  }

  static Future<void> _sign(String path) async {
    final cached = _signed[path];
    if (cached != null && cached.expires.isAfter(DateTime.now())) return;
    try {
      final url = await SupabaseService.client.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 60);
      _signed[path] = (
        url: url,
        expires: DateTime.now().add(const Duration(minutes: 55)),
      );
    } catch (error) {
      debugPrint('Profile picture could not be signed ($path): $error');
      _signed.remove(path);
    }
  }

  /// A signed URL for the signed-in user's own picture, or null.
  static Future<String?> myAvatarUrl() async {
    final path = await _currentPath();
    if (path == null) return null;
    await _sign(path);
    return _signed[path]?.url;
  }

  /// Uploads [bytes] as the new picture, then removes the previous file.
  static Future<void> setMyAvatar(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Choose an image up to 5 MB.');
    }
    final mime = imageMime(bytes); // throws for anything but PNG/JPEG/WebP
    final ext = mime == 'image/png'
        ? 'png'
        : mime == 'image/webp'
        ? 'webp'
        : 'jpg';
    final me = SupabaseService.userId;
    final client = SupabaseService.client;
    final previous = await _currentPath();
    final path = '$me/${const Uuid().v4()}.$ext';

    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    try {
      await client.from('profiles').update({'avatar_path': path}).eq('id', me);
    } catch (_) {
      // Don't leave an unused file behind if the profile couldn't be updated.
      await _removeQuietly(path);
      rethrow;
    }
    if (previous != null && previous != path) await _removeQuietly(previous);
    revision.value++;
  }

  /// Removes the picture; the profile goes back to showing initials.
  static Future<void> removeMyAvatar() async {
    final previous = await _currentPath();
    await SupabaseService.client
        .from('profiles')
        .update({'avatar_path': null})
        .eq('id', SupabaseService.userId);
    if (previous != null) await _removeQuietly(previous);
    revision.value++;
  }

  static Future<String?> _currentPath() async {
    final row = await SupabaseService.client
        .from('profiles')
        .select('avatar_path')
        .eq('id', SupabaseService.userId)
        .maybeSingle();
    return row?['avatar_path'] as String?;
  }

  static Future<void> _removeQuietly(String path) async {
    _signed.remove(path);
    try {
      await SupabaseService.client.storage.from(bucket).remove([path]);
    } catch (_) {
      // An orphaned file is harmless: it's private and never shown.
    }
  }
}
