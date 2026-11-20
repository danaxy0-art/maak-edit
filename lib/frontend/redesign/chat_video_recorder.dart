import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Records a chat video inside the app, so the user always has a close
/// button. (The phone's own camera app, opened through image_picker, often
/// has no way back on Android.)
///
/// Pops with the recorded [XFile], or with null when the user closes it.
class ChatVideoRecorderPage extends StatefulWidget {
  final Duration maxDuration;
  const ChatVideoRecorderPage({super.key, required this.maxDuration});
  @override
  State<ChatVideoRecorderPage> createState() => _ChatVideoRecorderPageState();
}

class _ChatVideoRecorderPageState extends State<ChatVideoRecorderPage>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _recording = false;
  bool _stopping = false;
  bool _released = false;
  int _seconds = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw StateError('no camera');
      final back = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = back < 0 ? 0 : back;
      await _open();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _open() async {
    final previous = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await previous?.dispose();
    final controller = CameraController(
      _cameras[_cameraIndex],
      // Medium keeps a 30-second clip well under the 10 MB chat limit.
      ResolutionPreset.medium,
      enableAudio: true,
    );
    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose();
      _fail(e);
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _error = null;
    });
  }

  void _fail(Object e) {
    if (!mounted) return;
    final denied =
        e is CameraException &&
        (e.code.contains('AccessDenied') || e.code.contains('Permission'));
    setState(
      () => _error = denied
          ? 'Allow camera and microphone access in your phone settings to record a video.'
          : 'Could not open the camera. Please try again.',
    );
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || _stopping) return;
    if (_recording) return _stop();
    try {
      await controller.startVideoRecording();
      _seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= widget.maxDuration.inSeconds) unawaited(_stop());
      });
      setState(() => _recording = true);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    if (controller == null || !_recording || _stopping) return;
    _stopping = true;
    _timer?.cancel();
    try {
      final file = await controller.stopVideoRecording();
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      _stopping = false;
      if (mounted) setState(() => _recording = false);
      _fail(e);
    }
  }

  Future<void> _close() async {
    if (_stopping) return; // already finishing and returning the video
    _stopping = true;
    _timer?.cancel();
    if (_recording) {
      // Discard a recording in progress.
      try {
        await _controller?.stopVideoRecording();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera in the background; reopen it on return.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_recording) {
        unawaited(_close());
        return;
      }
      // Only release a camera that is open: the permission prompt on first
      // use also pauses the app while the camera is still being opened.
      final controller = _controller;
      if (controller == null) return;
      _controller = null;
      _released = true;
      unawaited(controller.dispose());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _released) {
      _released = false;
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  String get _clock {
    final left = widget.maxDuration.inSeconds - _seconds;
    return '0:${left.clamp(0, 59).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: false,
      // The phone's Back button/gesture closes the recorder too.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : controller == null || !controller.value.isInitialized
                      ? const CircularProgressIndicator(color: Colors.white)
                      : CameraPreview(controller),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                ),
              ),
              if (_recording)
                Positioned(
                  top: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _clock,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              if (_error == null)
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 48),
                      Semantics(
                        button: true,
                        label: _recording ? 'Stop recording' : 'Start recording',
                        child: GestureDetector(
                          onTap: controller == null ? null : _toggleRecording,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            alignment: Alignment.center,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: _recording ? 30 : 60,
                              height: _recording ? 30 : 60,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(
                                  _recording ? 6 : 30,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: _cameras.length > 1 && !_recording
                            ? IconButton(
                                tooltip: 'Switch camera',
                                onPressed: _switchCamera,
                                icon: const Icon(
                                  Icons.cameraswitch_outlined,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
