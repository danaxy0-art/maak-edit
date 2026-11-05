import 'dart:async';

/// Runs only the latest edit after typing pauses; cancel when leaving a screen.
class DebouncedAction {
  final Duration delay;
  Timer? _timer;
  DebouncedAction({this.delay = const Duration(milliseconds: 650)});
  void schedule(void Function() action) {
    cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
