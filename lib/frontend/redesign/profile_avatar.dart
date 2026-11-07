import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../backend/services/avatar_service.dart';
import '../design/tokens.dart';
import 'feedback.dart';
import 'ui.dart';

/// The picture at the top of My profile, with a camera button to add, change
/// or remove it. Shows initials when there is no picture.
class ProfileAvatarEditor extends StatefulWidget {
  final String name;
  final double radius;
  const ProfileAvatarEditor({super.key, required this.name, this.radius = 48});
  @override
  State<ProfileAvatarEditor> createState() => _ProfileAvatarEditorState();
}

class _ProfileAvatarEditorState extends State<ProfileAvatarEditor> {
  String? _url;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    String? url;
    try {
      url = await AvatarService.myAvatarUrl();
    } catch (_) {
      url = null; // fall back to initials
    }
    if (mounted) {
      setState(() {
        _url = url;
        _busy = false;
      });
    }
  }

  Future<void> _change() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_url == null ? 'Add photo' : 'Change photo'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (_url != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'pick') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null || !mounted) return;
      await _run(() async {
        // Decode first so a corrupt file gives a clear error before upload.
        final image = await decodeImageFromList(bytes);
        image.dispose();
        await AvatarService.setMyAvatar(bytes);
      }, done: 'Profile photo updated.');
    } else {
      await _run(AvatarService.removeMyAvatar, done: 'Profile photo removed.');
    }
  }

  Future<void> _run(Future<void> Function() action, {required String done}) async {
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showAppError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    final fallback = Text(
      initials(widget.name),
      style: TextStyle(
        fontFamily: 'DMSans',
        fontSize: widget.radius * 0.62,
        fontWeight: FontWeight.w700,
      ),
    );
    return Semantics(
      button: true,
      label: _url == null ? 'Add profile photo' : 'Change profile photo',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: widget.radius,
              backgroundColor: MaakColors.selected,
              child: ClipOval(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: _url == null
                      ? Center(child: fallback)
                      : Image.network(
                          _url!,
                          fit: BoxFit.cover,
                          cacheWidth: (size * 3).round(),
                          errorBuilder: (context, error, stack) =>
                              Center(child: fallback),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : Center(child: fallback),
                        ),
                ),
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0x66FFFFFF),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            PositionedDirectional(
              end: -2,
              bottom: -2,
              child: Material(
                color: MaakColors.ink,
                shape: const CircleBorder(
                  side: BorderSide(color: Colors.white, width: 2),
                ),
                child: IconButton(
                  tooltip: _url == null
                      ? 'Add profile photo'
                      : 'Change profile photo',
                  onPressed: _busy ? null : _change,
                  icon: const Icon(
                    Icons.photo_camera_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
