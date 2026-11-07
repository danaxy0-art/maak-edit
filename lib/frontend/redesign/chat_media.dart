import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../backend/chat/chat_media_service.dart';
import '../../backend/services/supabase_service.dart';
import '../../backend/chat/chat_media_policy.dart';
import 'feedback.dart';

/// Picks, records and previews one attachment. It has no Send button of its
/// own: the chat's Send button calls [ChatMediaComposerState.sendDraft] (through
/// a GlobalKey) with the typed text as the caption.
class ChatMediaComposer extends StatefulWidget {
  final String requestId;
  final bool enabled;

  /// True while picking, recording, or uploading.
  final ValueChanged<bool> onBusy;

  /// True while an attachment is ready to send.
  final ValueChanged<bool> onDraftChanged;
  const ChatMediaComposer({
    super.key,
    required this.requestId,
    required this.enabled,
    required this.onBusy,
    required this.onDraftChanged,
  });
  @override
  State<ChatMediaComposer> createState() => ChatMediaComposerState();
}

class ChatMediaComposerState extends State<ChatMediaComposer>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _preview = AudioPlayer();
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  Completer<void>? _recordDone;
  final _pcm = BytesBuilder(copy: false);
  bool _recording = false, _busy = false, _previewPlaying = false;
  int _seconds = 0;
  ChatAttachment? _draft;
  String? _error;
  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    widget.onBusy(value || _recording);
  }

  bool get hasDraft => _draft != null;

  void _setDraft(ChatAttachment? draft) {
    if (!mounted) return;
    setState(() {
      _draft = draft;
      if (draft == null) _previewPlaying = false;
    });
    widget.onDraftChanged(draft != null);
  }

  /// Sends the attachment with [caption]. Returns true once it's sent; on
  /// failure the attachment is kept and the error is shown here.
  Future<bool> sendDraft({String caption = ''}) async {
    final draft = _draft;
    if (_busy || draft == null) return false;
    _setBusy(true);
    try {
      await _preview.stop();
      await ChatMediaService.send(widget.requestId, draft, caption: caption);
      if (mounted) setState(() => _error = null);
      _setDraft(null);
      return true;
    } catch (error) {
      if (mounted)
        setState(
          () => _error =
              'Not sent. Your attachment is kept. ${friendlyError(error)}',
        );
      return false;
    } finally {
      _setBusy(false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preview.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewPlaying = false);
    });
  }

  @override
  void didUpdateWidget(covariant ChatMediaComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled && _recording)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_stop(discard: true));
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording)
      unawaited(_stop(discard: true));
    if (state != AppLifecycleState.resumed) unawaited(_preview.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_recorder.dispose());
    unawaited(_preview.dispose());
    super.dispose();
  }

  Future<void> _pick({bool video = false}) async {
    if (_busy || !widget.enabled) return;
    _setBusy(true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: video ? ['mp4'] : ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || !mounted || !widget.enabled) return;
      final file = result.files.single;
      if (file.size > chatMediaLimit || file.bytes == null)
        throw ArgumentError(
          video
              ? 'Choose an MP4 video up to 10 MB.'
              : 'Choose an image up to 10 MB.',
        );
      final mime = video ? videoMime(file.bytes!) : imageMime(file.bytes!);
      // Decode before upload so corrupt images produce a clear error.
      if (!video) {
        final image = await decodeImageFromList(file.bytes!);
        image.dispose();
      }
      if (mounted) {
        setState(() => _error = null);
        _setDraft(
          ChatAttachment(
            id: const Uuid().v4(),
            kind: video ? 'video' : 'image',
            mime: mime,
            bytes: file.bytes!,
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _record() async {
    if (_busy || _recording || !widget.enabled) return;
    _setBusy(true);
    try {
      if (!await _recorder.hasPermission())
        throw ArgumentError(
          'Allow microphone access to record a voice message.',
        );
      if (!mounted || !widget.enabled) return;
      _pcm.clear();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      if (!mounted ||
          !widget.enabled ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await _recorder.stop();
        return;
      }
      setState(() {
        _recording = true;
        _seconds = 0;
        _error = null;
      });
      _recordDone = Completer<void>();
      _subscription = stream.listen(
        (chunk) {
          final remaining = 32000 * voiceSecondsLimit - _pcm.length;
          if (remaining > 0)
            _pcm.add(
              chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
            );
          if (_pcm.length >= 32000 * voiceSecondsLimit && !_busy)
            unawaited(_stop());
        },
        onDone: () {
          if (!(_recordDone?.isCompleted ?? true)) _recordDone!.complete();
        },
        onError: (Object error) {
          unawaited(_stop(discard: true));
          if (mounted)
            setState(() => _error = 'Recording failed. Please try again.');
        },
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
        if (_seconds >= voiceSecondsLimit) unawaited(_stop());
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _stop({bool discard = false}) async {
    if (!_recording || _busy) return;
    _setBusy(true);
    _timer?.cancel();
    try {
      await _recorder.stop();
      await _recordDone?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await _subscription?.cancel();
      _subscription = null;
      final pcm = _pcm.takeBytes();
      if (!discard && mounted && widget.enabled) {
        final wav = voiceWav(pcm);
        _setDraft(
          ChatAttachment(
            id: const Uuid().v4(),
            kind: 'voice',
            mime: 'audio/wav',
            bytes: wav,
            durationMs: pcm.length * 1000 ~/ 32000,
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _recording = false);
        _setBusy(false);
      }
    }
  }

  Future<void> _playPreview() async {
    try {
      if (_previewPlaying) {
        await _preview.pause();
      } else {
        await _preview.play(BytesSource(_draft!.bytes, mimeType: 'audio/wav'));
      }
      if (mounted) setState(() => _previewPlaying = !_previewPlaying);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = 'Could not play this recording. Please record it again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_error != null)
        Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      if (_draft case final draft?) ...[
        if (draft.kind == 'image')
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: Image.memory(draft.bytes, fit: BoxFit.contain),
          ),
        Row(
          children: [
            if (draft.kind == 'voice')
              IconButton(
                tooltip: 'Preview voice message',
                onPressed: _busy ? null : _playPreview,
                icon: Icon(_previewPlaying ? Icons.pause : Icons.play_arrow),
              ),
            Expanded(
              child: Text(
                _busy
                    ? 'Sending…'
                    : draft.kind == 'voice'
                    ? 'Voice message · ${(draft.durationMs! / 1000).ceil()}s'
                    : draft.kind == 'video'
                    ? 'MP4 video attached'
                    : 'Photo attached',
              ),
            ),
            IconButton(
              tooltip: 'Discard attachment',
              onPressed: _busy
                  ? null
                  : () async {
                      await _preview.stop();
                      if (mounted) setState(() => _error = null);
                      _setDraft(null);
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ] else if (_recording)
        Row(
          children: [
            const Icon(Icons.mic, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text('Recording $_seconds / 60s')),
            IconButton(
              tooltip: 'Cancel recording',
              onPressed: _busy ? null : () => _stop(discard: true),
              icon: const Icon(Icons.close),
            ),
            IconButton(
              tooltip: 'Stop and preview',
              onPressed: _busy ? null : _stop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        )
      else
        Row(
          children: [
            IconButton(
              tooltip: 'Attach image',
              onPressed: _busy || !widget.enabled ? null : _pick,
              icon: const Icon(Icons.image_outlined),
            ),
            IconButton(
              tooltip: 'Attach MP4 video',
              onPressed: _busy || !widget.enabled
                  ? null
                  : () => _pick(video: true),
              icon: const Icon(Icons.video_library_outlined),
            ),
            IconButton(
              tooltip: 'Record voice message',
              onPressed: _busy || !widget.enabled ? null : _record,
              icon: const Icon(Icons.mic_none),
            ),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
    ],
  );
}

class ChatMediaBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  const ChatMediaBubble({super.key, required this.message});
  @override
  State<ChatMediaBubble> createState() => _ChatMediaBubbleState();
}

class _ChatMediaBubbleState extends State<ChatMediaBubble>
    with WidgetsBindingObserver {
  late Future<String> _url;
  final _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _playing = false, _loading = false;
  Duration _position = Duration.zero;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _url = widget.message['message_type'] == 'image'
        ? ChatMediaService.signedUrl(
            widget.message['attachment_path'] as String,
          )
        : Future.value('');
    _subscriptions.add(
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
    );
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) {
        if (mounted)
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_player.pause());
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_playing) {
        await _player.pause();
      } else {
        // Refresh expiring private URL on every play/resume.
        final url = await ChatMediaService.signedUrl(
          widget.message['attachment_path'] as String,
        );
        await _player.play(
          UrlSource(url, mimeType: 'audio/wav'),
          position: _position,
        );
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (mounted)
        setState(() {
          _playing = false;
          _error = 'Could not play. Tap to retry.';
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message['message_type'] == 'video') {
      return OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ChatAttachmentPage(message: widget.message),
          ),
        ),
        icon: const Icon(Icons.play_circle_outline, size: 32),
        label: const Text('Video · Tap to play'),
      );
    }
    if (widget.message['message_type'] == 'voice') {
      final seconds = ((widget.message['duration_ms'] as num? ?? 0) / 1000)
          .ceil();
      return SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: _playing
                      ? 'Pause voice message'
                      : 'Play voice message',
                  onPressed: _loading ? null : _toggle,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_playing ? Icons.pause : Icons.play_arrow),
                ),
                const Icon(Icons.graphic_eq),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voice message\n${_position.inSeconds}s / ${seconds}s',
                  ),
                ),
              ],
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return TextButton.icon(
            onPressed: () => setState(
              () => _url = ChatMediaService.signedUrl(
                widget.message['attachment_path'] as String,
              ),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry photo'),
          );
        if (!snapshot.hasData)
          return const SizedBox(
            width: 180,
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        final url = snapshot.data!;
        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChatAttachmentPage(message: widget.message),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              width: 240,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => TextButton(
                onPressed: () => setState(
                  () => _url = ChatMediaService.signedUrl(
                    widget.message['attachment_path'] as String,
                  ),
                ),
                child: const Text('Retry photo'),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ChatVideoPage extends StatefulWidget {
  final String path;
  const ChatVideoPage({super.key, required this.path});
  @override
  State<ChatVideoPage> createState() => _ChatVideoPageState();
}

class _ChatVideoPageState extends State<ChatVideoPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final previous = _controller;
    _controller = null;
    previous?.removeListener(_changed);
    await previous?.dispose();
    VideoPlayerController? candidate;
    try {
      final url = await ChatMediaService.signedUrl(widget.path);
      candidate = VideoPlayerController.networkUrl(Uri.parse(url));
      await candidate.initialize();
      if (!mounted) {
        await candidate.dispose();
        return;
      }
      _controller = candidate;
      candidate.addListener(_changed);
      setState(() => _loading = false);
    } catch (_) {
      await candidate?.dispose();
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Video unavailable, deleted, or unsupported on this device.';
        });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Video')),
    body: Center(
      child: _loading
          ? const CircularProgressIndicator()
          : _error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                  VideoProgressIndicator(_controller!, allowScrubbing: true),
                  if (_controller!.value.hasError)
                    const Text('Playback failed. Try another MP4 file.'),
                  IconButton.filled(
                    tooltip: _controller!.value.isPlaying
                        ? 'Pause video'
                        : 'Play video',
                    icon: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    onPressed: () async {
                      try {
                        if (_controller!.value.isPlaying) {
                          await _controller!.pause();
                        } else {
                          await _controller!.play();
                        }
                      } catch (_) {
                        if (mounted)
                          setState(
                            () => _error =
                                'Could not play this video. Please retry.',
                          );
                      }
                    },
                  ),
                ],
              ),
            ),
    ),
  );
}

/// A live visibility check also removes an open photo/video after deletion.
class ChatAttachmentPage extends StatefulWidget {
  final Map<String, dynamic> message;
  const ChatAttachmentPage({super.key, required this.message});
  @override
  State<ChatAttachmentPage> createState() => _ChatAttachmentPageState();
}

class _ChatAttachmentPageState extends State<ChatAttachmentPage> {
  late final Stream<List<Map<String, dynamic>>> _stream;
  Future<String>? _url;
  @override
  void initState() {
    super.initState();
    _stream = SupabaseService.messageStream(
      widget.message['request_id'] as String,
    );
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          final available =
              snapshot.data?.any(
                (m) =>
                    m['id'] == widget.message['id'] && m['deleted_at'] == null,
              ) ??
              false;
          if (snapshot.hasError || (snapshot.hasData && !available))
            return Scaffold(
              appBar: AppBar(title: const Text('Attachment')),
              body: const Center(
                child: Text('This attachment is no longer available.'),
              ),
            );
          if (!snapshot.hasData)
            return Scaffold(
              appBar: AppBar(title: const Text('Attachment')),
              body: const Center(child: CircularProgressIndicator()),
            );
          if (widget.message['message_type'] == 'video')
            return ChatVideoPage(
              path: widget.message['attachment_path'] as String,
            );
          _url ??= ChatMediaService.signedUrl(
            widget.message['attachment_path'] as String,
          );
          return Scaffold(
            appBar: AppBar(title: const Text('Photo')),
            body: Center(
              child: FutureBuilder<String>(
                future: _url,
                builder: (context, url) => url.hasError
                    ? TextButton(
                        onPressed: () => setState(
                          () => _url = ChatMediaService.signedUrl(
                            widget.message['attachment_path'] as String,
                          ),
                        ),
                        child: const Text('Retry photo'),
                      )
                    : !url.hasData
                    ? const CircularProgressIndicator()
                    : InteractiveViewer(
                        child: Image.network(
                          url.data!,
                          errorBuilder: (_, _, _) => TextButton(
                            onPressed: () => setState(
                              () => _url = ChatMediaService.signedUrl(
                                widget.message['attachment_path'] as String,
                              ),
                            ),
                            child: const Text('Retry photo'),
                          ),
                        ),
                      ),
              ),
            ),
          );
        },
      );
}
