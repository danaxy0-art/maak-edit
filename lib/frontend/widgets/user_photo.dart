import 'package:flutter/material.dart';

import '../../backend/services/avatar_service.dart';
import '../../backend/services/supabase_service.dart';

/// Shows [userId]'s profile picture as a circle of [size], or [child] (the
/// usual initials circle) when they have no picture or it can't load.
/// Reloads as soon as the signed-in user changes their own picture.
class UserPhoto extends StatefulWidget {
  final String? userId;
  final double size;
  final Widget child;
  const UserPhoto({
    super.key,
    required this.userId,
    required this.size,
    required this.child,
  });
  @override
  State<UserPhoto> createState() => _UserPhotoState();
}

class _UserPhotoState extends State<UserPhoto> {
  String? _url;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    AvatarService.revision.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant UserPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _load();
  }

  @override
  void dispose() {
    AvatarService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.userId;
    final request = ++_request;
    if (id == null || id.isEmpty) {
      if (_url != null && mounted) setState(() => _url = null);
      return;
    }
    final url = await AvatarService.urlFor(id);
    if (mounted && request == _request && url != _url) {
      setState(() => _url = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) return widget.child;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: (widget.size * 3).round(),
          errorBuilder: (context, error, stack) => widget.child,
          loadingBuilder: (context, image, progress) =>
              progress == null ? image : widget.child,
        ),
      ),
    );
  }
}

/// The other person in a support request row (seeker_id / volunteer_id).
String? otherParticipantId(Map<String, dynamic> row) {
  final me = SupabaseService.currentUser?.id;
  final seeker = row['seeker_id'] as String?;
  final volunteer = row['volunteer_id'] as String?;
  return seeker == me ? volunteer : seeker;
}
