import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Rings for an incoming voice call while Ma'ak is open, and clears the
/// "Incoming voice call" push from the notification shade once the call is
/// answered, declined or over.
///
/// With the app closed or in the background, the push itself rings (send-push
/// uses the 'maak_calls' channel, tag `call-<request id>`). In the foreground
///  /// that push is not shown, so this plays assets/sounds/ringtone.wav in a loop
/// at ringtone volume (Android: it follows the ringer volume and silent mode).
class CallRinger {
  CallRinger._();

  static AudioPlayer? _player;
  static String? _ringingFor;

  static Future<void> start(String callId) async {
    if (_ringingFor == callId) return;
    await stop();
    // Don't play over the system ringtone when the app is in the background.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _ringingFor = callId;
    try {
      final player = AudioPlayer();
      _player = player;
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.notificationRingtone,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(),
        ),
      );
      await player.setReleaseMode(ReleaseMode.loop);
      // The call may have been answered while the player was starting.
      if (_ringingFor != callId) return;
      await player.play(AssetSource('sounds/ringtone.wav'));
    } catch (error) {
      if (kDebugMode) debugPrint('CallRinger: could not ring ($error)');
    }
  }

  static Future<void> stop() async {
    _ringingFor = null;
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
  }

  /// Removes the ringing push for [requestId] from the notification shade.
  /// Firebase shows a tagged notification with id 0.
  static Future<void> clearPush(String requestId) async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(id: 0, tag: 'call-$requestId');
    } catch (_) {}
  }
}
