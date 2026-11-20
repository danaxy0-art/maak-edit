import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'chat_media_policy.dart';

class ChatAttachment {
  final String id, kind, mime;
  final Uint8List bytes;
  final int? durationMs;
  const ChatAttachment({
    required this.id,
    required this.kind,
    required this.mime,
    required this.bytes,
    this.durationMs,
  });
  String get extension => mime == 'image/jpeg'
      ? 'jpg'
      : mime == 'image/png'
      ? 'png'
      : mime == 'image/webp'
      ? 'webp'
      : mime == 'video/mp4'
      ? 'mp4'
      : 'wav';
}

class ChatMediaService {
  static const bucket = 'chat-media';
  // A stable message ID makes a retry after a lost response safe.
  /// [caption] is optional text sent with the attachment (up to 2000 chars).
  static Future<void> send(
    String requestId,
    ChatAttachment attachment, {
    String caption = '',
  }) async {
    final text = caption.trim();
    if (text.length > 2000) throw ArgumentError('Caption is too long.');
    final client = SupabaseService.client;
    final me = SupabaseService.userId;
    final path = '$requestId/$me/${attachment.id}.${attachment.extension}';
    final existing = await client
        .from('messages')
        .select('id')
        .eq('id', attachment.id)
        .maybeSingle();
    if (existing != null) return;
    if (attachment.bytes.isEmpty || attachment.bytes.length > chatMediaLimit)
      throw ArgumentError('File must be up to 10 MB.');
    if (attachment.kind == 'image' &&
        imageMime(attachment.bytes) != attachment.mime)
      throw ArgumentError('Invalid image.');
    if (attachment.kind == 'video' &&
        videoMime(attachment.bytes) != attachment.mime)
      throw ArgumentError('Invalid MP4 video.');
    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            attachment.bytes,
            fileOptions: FileOptions(
              contentType: attachment.mime,
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      // Only this account can create this unique path. A timed-out upload can be retried.
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
    }
    try {
      await client.from('messages').insert({
        'id': attachment.id,
        'request_id': requestId,
        'sender_id': me,
        'body': text.isNotEmpty ? text : chatMediaDefaultBody(attachment.kind),
        'message_type': attachment.kind,
        'attachment_path': path,
        'attachment_mime': attachment.mime,
        'attachment_bytes': attachment.bytes.length,
        'duration_ms': attachment.durationMs,
      });
    } catch (error, stack) {
      try {
        if (await client
                .from('messages')
                .select('id')
                .eq('id', attachment.id)
                .maybeSingle() !=
            null)
          return;
      } catch (_) {
        /* Preserve original error. Keep the upload for a safe retry. */
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<String> signedUrl(String path) =>
      SupabaseService.client.storage.from(bucket).createSignedUrl(path, 300);
}
