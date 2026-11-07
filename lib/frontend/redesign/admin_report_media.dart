// Admin report media (20261107130000_admin_report_media.sql). Shows the photo,
// voice message or video of a reported message, and of its ±5 context while the
// report is open. The server decides what an Admin may open: every file comes
// from a 60-second signed URL that Storage signs only for an allowed path. Signed
// URLs live in memory only and are never logged or stored.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../backend/services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Audio playback used by [AdminReportMediaView].
abstract class AdminAudioSession {
  Stream<void> get completed;
  Future<void> play(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> close();
}

/// Video playback used by [AdminReportVideoPage].
abstract class AdminVideoSession implements Listenable {
  Future<void> initialize();
  double get aspectRatio;
  bool get isPlaying;
  bool get hasError;
  Future<void> play();
  Future<void> pause();
  Widget view();
  Future<void> close();
}

/// Platform players need a device, so widget tests replace these.
class AdminReportMediaPlayers {
  static AdminAudioSession Function() audio = _PluginAudio.new;
  static AdminVideoSession Function(Uri url) video = _PluginVideo.new;
  static ImageProvider Function(String url) image = (url) => NetworkImage(url);
}

class _PluginAudio implements AdminAudioSession {
  final _player = AudioPlayer();
  @override
  Stream<void> get completed => _player.onPlayerComplete;
  @override
  Future<void> play(String url) =>
      _player.play(UrlSource(url, mimeType: 'audio/wav'));
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> close() => _player.dispose();
}

class _PluginVideo extends ChangeNotifier implements AdminVideoSession {
  _PluginVideo(Uri url) : _c = VideoPlayerController.networkUrl(url) {
    _c.addListener(notifyListeners);
  }
  final VideoPlayerController _c;
  @override
  Future<void> initialize() => _c.initialize();
  @override
  double get aspectRatio => _c.value.aspectRatio;
  @override
  bool get isPlaying => _c.value.isPlaying;
  @override
  bool get hasError => _c.value.hasError;
  @override
  Future<void> play() => _c.play();
  @override
  Future<void> pause() => _c.pause();
  @override
  Widget view() => VideoPlayer(_c);
  @override
  Future<void> close() async {
    _c.removeListener(notifyListeners);
    await _c.dispose();
    dispose();
  }
}

const _supportedMime = {
  'image': {'image/png', 'image/jpeg', 'image/webp'},
  'voice': {'audio/wav'},
  'video': {'video/mp4'},
};

String _kindLabel(String? type) => switch (type) {
  'image' => 'Photo',
  'voice' => 'Voice message',
  'video' => 'Video',
  _ => 'Attachment',
};

String _unavailableText(String? type, String? reason) => switch (reason) {
  'conversation_deleted' =>
    '${_kindLabel(type)} is no longer available because the conversation was deleted.',
  'file_missing' || 'missing' =>
    '${_kindLabel(type)} is no longer available. The file was removed.',
  'unsupported' => 'This media type can\'t be shown in the app.',
  _ => '${_kindLabel(type)} is not available.',
};

/// Readable message for a failed signed URL or load. Never includes the URL.
String _loadError(Object error) {
  debugPrint('Report media load failed: ${error.runtimeType}');
  if (error is StorageException &&
      {'400', '403', '404'}.contains(error.statusCode)) {
    return 'This media is no longer available.';
  }
  return 'Could not load this media. Check your connection and try again.';
}

/// One media item from admin_report_media.
class AdminReportMediaView extends StatelessWidget {
  final Map<String, dynamic> item;
  const AdminReportMediaView({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final type = item['message_type'] as String?;
    final path = item['path'] as String?;
    final supported = _supportedMime[type]?.contains(item['mime']) ?? false;
    if (item['available'] != true || path == null || !supported) {
      return _Notice(
        key: const ValueKey('report_media_unavailable'),
        icon: Icons.hide_image_outlined,
        text: _unavailableText(
          type,
          item['available'] == true
              ? 'unsupported'
              : item['unavailable_reason'] as String?,
        ),
      );
    }
    return switch (type) {
      'image' => _AdminImage(path: path),
      'voice' => _AdminVoice(
        path: path,
        durationMs: item['duration_ms'] as int?,
      ),
      _ => _AdminVideoTile(path: path),
    };
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.divider.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: AppColors.textMuted)),
        ),
        if (onRetry != null)
          TextButton(
            key: const ValueKey('report_media_retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
      ],
    ),
  );
}

class _AdminImage extends StatefulWidget {
  final String path;
  const _AdminImage({required this.path});
  @override
  State<_AdminImage> createState() => _AdminImageState();
}

class _AdminImageState extends State<_AdminImage> {
  late Future<String> _url = SupabaseService.reportMediaUrl(widget.path);

  void _retry() {
    final url = SupabaseService.reportMediaUrl(widget.path);
    setState(() {
      _url = url;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snap) {
      if (snap.hasError) {
        return _Notice(
          icon: Icons.broken_image_outlined,
          text: _loadError(snap.error!),
          onRetry: _retry,
        );
      }
      if (!snap.hasData) {
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final provider = AdminReportMediaPlayers.image(snap.data!);
      return Semantics(
        button: true,
        label: 'Reported photo. Tap to enlarge.',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Photo')),
                backgroundColor: Colors.black,
                body: Center(
                  child: InteractiveViewer(
                    child: Image(
                      image: provider,
                      errorBuilder: (_, _, _) => const Text(
                        'Could not load this photo.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: Image(
                key: const ValueKey('report_media_image'),
                image: provider,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _Notice(
                  icon: Icons.broken_image_outlined,
                  text:
                      'Could not load this photo. It may be damaged or no longer available.',
                  onRetry: _retry,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AdminVoice extends StatefulWidget {
  final String path;
  final int? durationMs;
  const _AdminVoice({required this.path, this.durationMs});
  @override
  State<_AdminVoice> createState() => _AdminVoiceState();
}

class _AdminVoiceState extends State<_AdminVoice> {
  AdminAudioSession? _session;
  StreamSubscription<void>? _done;
  bool _playing = false, _started = false, _busy = false;
  String? _error;

  Future<void> _toggle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_playing) {
        await _session!.pause();
      } else if (_started) {
        await _session!.resume();
      } else {
        final session = _session ??= AdminReportMediaPlayers.audio();
        _done ??= session.completed.listen((_) {
          if (mounted) {
            setState(() {
              _playing = false;
              _started = false;
            });
          }
        });
        // A fresh short-lived URL for every start.
        await session.play(await SupabaseService.reportMediaUrl(widget.path));
        _started = true;
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (error) {
      _started = false;
      if (mounted) {
        setState(() {
          _playing = false;
          _error = _loadError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_done?.cancel());
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.durationMs == null
        ? null
        : (widget.durationMs! / 1000).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              key: const ValueKey('report_media_play'),
              tooltip: _playing ? 'Pause voice message' : 'Play voice message',
              onPressed: _busy ? null : _toggle,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _playing
                    ? 'Playing voice message'
                    : seconds == null
                    ? 'Voice message'
                    : 'Voice message · ${seconds}s',
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '$_error Tap play to retry.',
              key: const ValueKey('report_media_error'),
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

class _AdminVideoTile extends StatelessWidget {
  final String path;
  const _AdminVideoTile({required this.path});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('report_media_video_open'),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AdminReportVideoPage(path: path)),
    ),
    icon: const Icon(Icons.play_circle_outline),
    label: const Text('Play video'),
  );
}

/// Full-screen player for one reported or context video.
class AdminReportVideoPage extends StatefulWidget {
  final String path;
  const AdminReportVideoPage({super.key, required this.path});
  @override
  State<AdminReportVideoPage> createState() => _AdminReportVideoPageState();
}

class _AdminReportVideoPageState extends State<AdminReportVideoPage> {
  AdminVideoSession? _session;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final previous = _session;
    _session = null;
    previous?.removeListener(_changed);
    await previous?.close();
    AdminVideoSession? candidate;
    try {
      final url = await SupabaseService.reportMediaUrl(widget.path);
      candidate = AdminReportMediaPlayers.video(Uri.parse(url));
      await candidate.initialize();
      if (!mounted) {
        await candidate.close();
        return;
      }
      candidate.addListener(_changed);
      setState(() {
        _session = candidate;
        _loading = false;
      });
    } catch (error) {
      await candidate?.close();
      final message = _loadError(error);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is StorageException
              ? message
              : 'Could not play this video. It may be damaged, unsupported on this device, or no longer available.';
        });
      }
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Reported video')),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null || s == null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error ?? 'Could not play this video.',
                      key: const ValueKey('report_media_error'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const ValueKey('report_media_retry'),
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: AspectRatio(
                        aspectRatio: s.aspectRatio > 0 ? s.aspectRatio : 16 / 9,
                        child: s.view(),
                      ),
                    ),
                    if (s.hasError)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Playback failed. Tap Retry to load it again.',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filled(
                          key: const ValueKey('report_media_play'),
                          tooltip: s.isPlaying ? 'Pause video' : 'Play video',
                          icon: Icon(
                            s.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          onPressed: () async {
                            try {
                              s.isPlaying ? await s.pause() : await s.play();
                            } catch (error) {
                              _loadError(error);
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'Could not play this video. Tap Retry.',
                                );
                              }
                            }
                          },
                        ),
                        if (s.hasError)
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
