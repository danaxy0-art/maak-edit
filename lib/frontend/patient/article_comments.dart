import 'package:flutter/material.dart';

import '../../backend/services/health_library_service.dart';
import '../design/tokens.dart';
import '../redesign/feedback.dart';
import '../redesign/member_profile.dart';
import '../redesign/ui.dart' show initials;
import '../widgets/user_photo.dart';

/// Comments and replies under a Health Library article.
///
/// Members (help seekers and approved volunteers) post comments, reply to any
/// comment and delete their own. A reply to a reply joins the same thread; the
/// database notifies the author of the comment being answered.
/// With [moderator] (Admin), the composer is hidden and every comment can be
/// deleted.
class ArticleCommentsSection extends StatefulWidget {
  final String articleId;
  final bool moderator;

  /// Called with the new total after the list loads or changes.
  final ValueChanged<int>? onCountChanged;

  /// Side margins for the heading and comments. The comment box ignores
  /// them and spans the full width, attached under the last comment.
  final EdgeInsetsGeometry contentPadding;

  const ArticleCommentsSection({
    super.key,
    required this.articleId,
    this.moderator = false,
    this.onCountChanged,
    this.contentPadding = EdgeInsets.zero,
  });

  @override
  State<ArticleCommentsSection> createState() => _ArticleCommentsSectionState();
}

class _ArticleCommentsSectionState extends State<ArticleCommentsSection> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _comments = [];
  Map<String, dynamic>? _replyTo;
  final Set<String> _deleting = {};
  bool _loading = true;
  bool _sending = false;
  Object? _error;
  int _request = 0;

  bool get _canPost => !widget.moderator;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await HealthLibraryService.getComments(widget.articleId);
      if (!mounted || request != _request) return;
      setState(() {
        _comments = rows;
        _loading = false;
        // The comment being answered may have been deleted meanwhile.
        if (_replyTo != null &&
            !rows.any((c) => c['id'] == _replyTo!['id'] && c['is_deleted'] != true)) {
          _replyTo = null;
        }
      });
      widget.onCountChanged?.call(rows.where((c) => c['is_deleted'] != true).length);
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _startReply(Map<String, dynamic> comment) {
    setState(() => _replyTo = comment);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final replying = _replyTo != null;
    setState(() => _sending = true);
    try {
      await HealthLibraryService.addComment(
        widget.articleId,
        text,
        replyToId: _replyTo?['id'] as String?,
      );
      if (!mounted) return;
      _text.clear();
      _focus.unfocus();
      setState(() => _replyTo = null);
      showSuccess(context, replying ? 'Reply posted.' : 'Comment posted.');
      await _load();
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> comment) async {
    final id = comment['id'] as String;
    // Matches the database: replies in its thread, or replies answering it.
    final hasReplies =
        _comments.any((c) => c['parent_id'] == id || c['reply_to_id'] == id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete comment?'),
        content: Text(
          hasReplies
              ? 'Your comment will show as "This message was deleted by the user." The replies to it will stay. This cannot be undone.'
              : 'This comment will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MaakColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(id));
    try {
      await HealthLibraryService.deleteComment(id);
      if (!mounted) return;
      showSuccess(context, 'Comment deleted.');
      await _load();
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _deleting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = _comments.where((c) => c['parent_id'] == null).toList();
    final replies = <String, List<Map<String, dynamic>>>{};
    for (final c in _comments) {
      final parent = c['parent_id'] as String?;
      if (parent != null) replies.putIfAbsent(parent, () => []).add(c);
    }
    final visibleCount = _comments.where((c) => c['is_deleted'] != true).length;
    // No cards or borders: the heading, the threads and the comment box sit
    // directly on the page, full width, separated by thin lines.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: widget.contentPadding,
          child: Row(
            children: [
              const Icon(Icons.forum_outlined, color: MaakColors.ink, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _loading && _comments.isEmpty
                        ? 'Comments'
                        : 'Comments ($visibleCount)',
                    style: MaakText.section,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh comments',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
        if (_loading && _comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null && _comments.isEmpty)
          _notice(
            Icons.cloud_off_outlined,
            'Could not load comments',
            friendlyError(_error!),
            action: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          )
        else if (top.isEmpty)
          _notice(
            Icons.chat_bubble_outline,
            'No comments yet',
            _canPost
                ? 'Share your thoughts or questions about this article.'
                : 'Comments from members will appear here.',
          )
        else
          for (final comment in top) ...[
            const Divider(height: 1, thickness: 1, color: MaakColors.border),
            _thread(comment, replies[comment['id']] ?? const []),
          ],
        if (_canPost) _composer() else const SizedBox(height: 24),
      ],
    );
  }

  Widget _composer() {
    final replyName = (_replyTo?['author_name'] ?? '').toString();
    final length = _text.text.runes.length;
    final canSend = !_sending && _text.text.trim().isNotEmpty;
    return Container(
      // Flat and full width on the page background, under a thin line like
      // the ones between comments.
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MaakColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        8,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_replyTo != null)
            Row(
              children: [
                const Icon(Icons.reply, size: 16, color: MaakColors.coralDeep),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Replying to $replyName',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MaakColors.coralDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel reply',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : () => setState(() => _replyTo = null),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: HealthLibraryService.maxCommentLength,
                  // No built-in counter: the bar stays slim; a count shows
                  // below only near the limit.
                  buildCounter: (
                    BuildContext context, {
                    required int currentLength,
                    required int? maxLength,
                    required bool isFocused,
                  }) =>
                      null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _replyTo == null ? 'Write a comment...' : 'Write a reply...',
                    isDense: true,
                    filled: true,
                    fillColor: MaakColors.surface,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: MaakColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: MaakColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: MaakColors.ink),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: _replyTo == null ? 'Post comment' : 'Post reply',
                onPressed: canSend ? _send : null,
                style: IconButton.styleFrom(
                  backgroundColor: MaakColors.button,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: MaakColors.border,
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 20),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Be kind. Do not share personal medical details.',
                    style: TextStyle(fontSize: 12, color: MaakColors.muted),
                  ),
                ),
                if (length > HealthLibraryService.maxCommentLength - 200)
                  Text(
                    '$length/${HealthLibraryService.maxCommentLength}',
                    style: TextStyle(
                      fontSize: 12,
                      color: length > HealthLibraryService.maxCommentLength
                          ? MaakColors.error
                          : MaakColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thread(Map<String, dynamic> comment, List<Map<String, dynamic>> replies) =>
      Padding(
        padding: widget.contentPadding.add(const EdgeInsets.symmetric(vertical: 12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _comment(comment),
            // Replies hang off a thin line that starts under the avatar.
            if (replies.isNotEmpty)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 16, top: 6),
                padding: const EdgeInsetsDirectional.only(start: 16),
                decoration: const BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(color: MaakColors.border, width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final reply in replies)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: _comment(reply),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _comment(Map<String, dynamic> c) {
    final id = c['id'] as String;
    // Every comment uses the same layout (photo, name line, text), so a
    // deleted comment or one from a removed account is as tall as the others:
    //  * deleted by its author: "[deleted]" and "This message was deleted by
    //    the user."
    //  * author deleted their account / account deactivated: the text stays,
    //    with "[deleted account]" / "[deactivated account]" as the name.
    final removed = c['is_deleted'] == true;
    final status = (c['author_status'] ?? 'active').toString();
    final placeholder = removed || status != 'active';
    final name = removed
        ? '[deleted]'
        : switch (status) {
            'deleted' => '[deleted account]',
            'deactivated' => '[deactivated account]',
            _ => (c['author_name'] ?? 'A member').toString(),
          };
    final role = switch (placeholder ? null : c['author_role']) {
      'volunteer' => 'Volunteer',
      'help_seeker' => 'Help seeker',
      _ => null,
    };
    final mine = c['is_mine'] == true;
    final deleting = _deleting.contains(id);
    // Name the person answered when a reply is to someone other than the
    // thread's first comment.
    final replyToName = c['reply_to_name'] as String?;
    final answeredOther = c['parent_id'] != null &&
        c['reply_to_id'] != null &&
        c['reply_to_id'] != c['parent_id'] &&
        replyToName != null;
    final canReply = _canPost && !removed;
    final canDelete = !removed && (mine || widget.moderator);
    final authorId = placeholder ? null : c['user_id'] as String?;
    // Tapping the photo or the name opens the author's profile.
    void openProfile() {
      if (authorId != null) {
        MemberProfilePage.open(context, userId: authorId, name: name);
      }
    }
    return Opacity(
      opacity: deleting ? 0.5 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (placeholder)
            const CircleAvatar(
              key: ValueKey('comment_placeholder_photo'),
              radius: 17,
              backgroundColor: MaakColors.border,
              child: Icon(Icons.person_off_outlined, size: 16, color: MaakColors.muted),
            )
          else
          Semantics(
            button: true,
            label: "Open $name's profile",
            excludeSemantics: true,
            child: InkWell(
              onTap: authorId == null ? null : openProfile,
              customBorder: const CircleBorder(),
              child: UserPhoto(
                userId: authorId,
                size: 34,
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: MaakColors.blush,
                  child: Text(
                    initials(name),
                    style: const TextStyle(fontSize: 12, color: MaakColors.ink),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One line for every comment: the name shrinks (ending in
                // "...") when it is long, e.g. "[deactivated account]" or a
                // long full name, so the badge and time never drop to a new
                // line. "(you)" is never cut off.
                Row(
                  key: ValueKey('comment_name_line_$id'),
                  children: [
                    Flexible(
                      child: InkWell(
                        onTap: authorId == null ? null : openProfile,
                        borderRadius: BorderRadius.circular(6),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: placeholder ? MaakColors.muted : MaakColors.ink,
                          ),
                        ),
                      ),
                    ),
                    if (mine)
                      const Text(
                        ' (you)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: MaakColors.ink,
                        ),
                      ),
                    if (role != null) ...[
                      const SizedBox(width: 8),
                      _RoleBadge(role),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      commentTimeAgo(c['created_at']?.toString()),
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12, color: MaakColors.muted),
                    ),
                  ],
                ),
                if (answeredOther) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Replying to $replyToName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: MaakColors.coralDeep),
                  ),
                ],
                const SizedBox(height: 4),
                if (removed)
                  const Text(
                    'This message was deleted by the user.',
                    style: TextStyle(
                      color: MaakColors.muted,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  )
                else
                  SelectableText(
                    (c['body'] ?? '').toString(),
                    style: const TextStyle(color: MaakColors.ink, height: 1.5),
                  ),
              ],
            ),
          ),
          // Reply and Delete live in the three-dot menu on the right.
          if (canReply || canDelete)
            PopupMenuButton<String>(
              tooltip: 'Comment options',
              enabled: !deleting,
              icon: const Icon(Icons.more_vert, size: 20, color: MaakColors.muted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 150),
              color: MaakColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (action) {
                if (action == 'reply') _startReply(c);
                if (action == 'delete') _delete(c);
              },
              itemBuilder: (context) => [
                if (canReply)
                  PopupMenuItem(
                    value: 'reply',
                    enabled: !_sending,
                    child: const Row(children: [
                      Icon(Icons.reply, size: 18, color: MaakColors.ink),
                      SizedBox(width: 10),
                      Text('Reply'),
                    ]),
                  ),
                if (canDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 18, color: MaakColors.error),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: MaakColors.error)),
                    ]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _notice(IconData icon, String title, String message, {Widget? action}) =>
      Padding(
        padding: widget.contentPadding.add(const EdgeInsets.symmetric(vertical: 22)),
        child: Column(
          children: [
            Icon(icon, color: MaakColors.coralDeep, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, color: MaakColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: MaakColors.muted, height: 1.45),
            ),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      );
}

/// "Just now", "5 min", "3 h", "2 days", "1 week", "3 weeks". No "ago",
/// so the label stays short next to long names.
String commentTimeAgo(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return '';
  final local = parsed.toLocal();
  final d = DateTime.now().difference(local);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inDays < 1) return '${d.inHours} h';
  if (d.inDays < 7) return d.inDays == 1 ? '1 day' : '${d.inDays} days';
  final weeks = d.inDays ~/ 7;
  return weeks == 1 ? '1 week' : '$weeks weeks';
}

/// Compact role label next to a commenter's name, in the app's role colours
/// (the same tints as RoleChip: peach for volunteers, pink for help seekers).
class _RoleBadge extends StatelessWidget {
  final String label;
  const _RoleBadge(this.label);

  @override
  Widget build(BuildContext context) {
    final volunteer = label == 'Volunteer';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: volunteer ? MaakColors.orbPeach : MaakColors.orbPink,
        borderRadius: BorderRadius.circular(MaakRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: volunteer ? const Color(0xFF8A4B1F) : const Color(0xFF8E2457),
        ),
      ),
    );
  }
}
