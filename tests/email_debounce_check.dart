import '../lib/backend/validation/debounced_action.dart';

Future<void> main() async {
  final calls = <String>[];
  final debounce = DebouncedAction(delay: const Duration(milliseconds: 30));
  debounce.schedule(() => calls.add('old@example.com'));
  debounce.schedule(() => calls.add('current@example.com'));
  if (calls.isNotEmpty) throw StateError('Checked before typing paused');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  if (calls.join(',') != 'current@example.com')
    throw StateError('Did not check only latest edit');
  print('PASS waits for pause and only checks latest edit');
  debounce.schedule(() => calls.add('canceled@example.com'));
  debounce.cancel();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  if (calls.length != 1)
    throw StateError('Disposed screen still checked email');
  print('PASS cancellation prevents deferred lookup');
}
