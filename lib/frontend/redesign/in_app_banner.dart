// ADDED: pop-up banner for a notification that arrives while the app is open. New file.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../design/tokens.dart';

/// Shows a banner at the top of [child] whenever a NEW unread notification
/// arrives. Notifications that already exist when the screen opens are not
/// shown (the bell badge covers those). Tap opens it through [onOpen].
class NotificationBannerHost extends StatefulWidget {
  final Widget child;
  final void Function(Map<String, dynamic> notification) onOpen;

  /// Test hook: replaces the Supabase notification stream.
  final Stream<List<Map<String, dynamic>>>? stream;
  final Duration visibleFor;

  /// ADDED: when false (Help Seeker) nothing is subscribed and no banner shows.
  final bool enabled;
  const NotificationBannerHost({
    super.key,
    required this.child,
    required this.onOpen,
    this.enabled = true,
    this.stream,
    this.visibleFor = const Duration(seconds: 5),
  });
  @override
  State<NotificationBannerHost> createState() => _NotificationBannerHostState();
}

class _NotificationBannerHostState extends State<NotificationBannerHost> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Set<String>? _seen; // null until the first snapshot arrives
  Map<String, dynamic>? _current;
  int _extra = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return; // ADDED: volunteer only
    _sub = (widget.stream ?? SupabaseService.notificationStream()).listen(
      _onRows,
      onError: (Object _) {}, // a failed stream must never break the app
    );
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    final ids = {for (final r in rows) '${r['id']}'};
    final seen = _seen;
    _seen = {...?seen, ...ids};
    if (seen == null || !mounted) return; // first snapshot = baseline
    final fresh = rows
        .where((r) => r['is_read'] == false && !seen.contains('${r['id']}'))
        .toList();
    if (fresh.isEmpty) return;
    // `fresh` is newest first (the stream is ordered by created_at desc).
    setState(() {
      _current = fresh.first;
      _extra = fresh.length - 1;
    });
    _timer?.cancel();
    _timer = Timer(widget.visibleFor, _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    if (mounted && _current != null) setState(() => _current = null);
  }

  void _open() {
    final n = _current;
    _dismiss();
    if (n != null) widget.onOpen(n);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child; // ADDED: volunteer only
    final n = _current;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: n == null
                  ? const SizedBox.shrink(key: ValueKey('no_banner'))
                  : Padding(
                      key: ValueKey('banner_${n['id']}'),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Semantics(
                            liveRegion: true,
                            child: Material(
                              color: MaakColors.ink,
                              elevation: 6,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: _open,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    6,
                                    12,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.notifications_active_outlined,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${n['title'] ?? 'Notification'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              _extra > 0
                                                  ? '${n['body'] ?? ''}  (+$_extra more)'
                                                  : '${n['body'] ?? ''}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        key: const ValueKey('banner_close'),
                                        tooltip: 'Dismiss',
                                        onPressed: _dismiss,
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}