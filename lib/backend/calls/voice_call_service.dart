import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/supabase_service.dart';

/// One audio session per signed-in client. Signalling is participant-only SQL;
/// audio travels over WebRTC, never through the reporting tables.
class VoiceCallService extends ChangeNotifier {
  static final instance = VoiceCallService._();
  VoiceCallService._();
  Map<String, dynamic>? call;
  bool busy = false, muted = false;
  String? error;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  RTCVideoRenderer? remoteAudio;
  Timer? _timer;
  int _revision = 0;
  bool _polling = false, _remoteSet = false, _accepting = false;
  String? _sessionUser;
  String? _pendingEnd;
  DateTime _lastBeat = DateTime(2000);
  final List<Map<String, dynamic>> _pendingIce = [];
  final Set<int> _receivedIce = {};
  bool get active =>
      call != null && {'calling', 'connected'}.contains(call!['status']);
  bool get incoming =>
      active &&
      call!['callee_id'] == SupabaseService.currentUser?.id &&
      call!['accepted_at'] == null;
  String get status => call?['status']?.toString() ?? 'calling';
  String get statusLabel => switch (status) {
    'connected' => 'Connected',
    'ended' => 'Ended',
    'missed' => 'Missed',
    _ =>
      call?['accepted_at'] != null
          ? 'Calling · connecting audio…'
          : incoming
          ? 'Incoming voice call'
          : 'Calling…',
  };
  void startWatching() {
    _sessionUser = SupabaseService.currentUser?.id;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<Map<String, dynamic>?> action(
    String action, {
    String? id,
    String? requestId,
    Map<String, dynamic>? payload,
  }) async {
    final value = await SupabaseService.client
        .rpc(
          'voice_call_action',
          params: {
            'p_action': action,
            'p_call_id': id ?? call?['id'],
            'p_request_id': requestId,
            'p_payload': payload ?? <String, dynamic>{},
          },
        )
        .timeout(const Duration(seconds: 12));
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static String message(Object e) {
    final text = e.toString();
    if (text.contains('participant_busy')) {
      return 'One participant is already in a call.';
    }
    if (text.contains('conversation_unavailable')) {
      return 'Calls require an accepted, open conversation.';
    }
    if (text.contains('23505')) return 'You have already reported this call.';
    if (text.toLowerCase().contains('permission') ||
        text.toLowerCase().contains('notallowed')) {
      return 'Allow microphone access to use voice calls.';
    }
    return 'Could not complete this action. Check your connection and try again.';
  }

  Future<void> _prepare(String requestId) async {
    _remoteSet = false;
    _receivedIce.clear();
    _pendingIce.clear();
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    remoteAudio = renderer;
    // Supply short-lived TURN credentials with --dart-define=VOICE_ICE_SERVERS.
    // Never ship a permanent TURN password in source control.
    dynamic servers = jsonDecode(
      const String.fromEnvironment(
        'VOICE_ICE_SERVERS',
        defaultValue: '[{"urls":"stun:stun.l.google.com:19302"}]',
      ),
    );
    if (const bool.fromEnvironment('VOICE_USE_TURN')) {
      final response = await SupabaseService.client.functions.invoke(
        'voice-ice-config',
        body: {'request_id': requestId},
      );
      if (response.data is! Map ||
          (response.data as Map)['iceServers'] is! List) {
        throw StateError('TURN configuration is unavailable');
      }
      servers = (response.data as Map)['iceServers'];
    }
    _pc = await createPeerConnection({
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    });
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _pendingIce.add(Map<String, dynamic>.from(candidate.toMap()));
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        notifyListeners();
      }
    };
    _pc!.onConnectionState = (state) async {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          active) {
        try {
          await action('connected');
        } catch (_) {
          /* next poll retries */
        }
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          active) {
        error =
            'Audio connection failed. End the call and try again, or report the issue.';
        notifyListeners();
      }
    };
    for (final track in _local!.getAudioTracks()) {
      await _pc!.addTrack(track, _local!);
    }
  }

  Future<void> start(String requestId) async {
    if (busy || active) return;
    _revision++;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _prepare(requestId);
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      call = await action(
        'start',
        requestId: requestId,
        payload: {'type': offer.type, 'sdp': offer.sdp},
      );
      _sessionUser = SupabaseService.userId;
    } catch (e) {
      error = message(e);
      await _release();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> accept() async {
    if (busy || !incoming) return;
    _revision++;
    busy = true;
    _accepting = true;
    error = null;
    notifyListeners();
    try {
      final id = call!['id'] as String;
      final offer = Map<String, dynamic>.from(call!['offer'] as Map);
      await _prepare(call!['request_id'] as String);
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          offer['sdp'] as String?,
          offer['type'] as String?,
        ),
      );
      _remoteSet = true;
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      final updated = await action(
        'accept',
        id: id,
        payload: {'type': answer.type, 'sdp': answer.sdp},
      );
      call = updated;
      if (!active) await _release();
    } catch (e) {
      error = message(e);
      await _release();
    } finally {
      busy = false;
      _accepting = false;
      notifyListeners();
    }
  }

  Future<void> end({bool reject = false}) async {
    if (busy || !active) return;
    _revision++;
    busy = true;
    error = null;
    notifyListeners();
    try {
      // Stop microphone immediately, even if signalling is offline.
      await _release();
      call = await action(reject ? 'reject' : 'end');
    } catch (e) {
      _pendingEnd = call?['id'] as String?;
      call = {...?call, 'status': 'ended', 'end_reason': 'local_hangup'};
      error = 'Call ended on this device. Waiting to notify your peer.';
    } finally {
      await _release();
      busy = false;
      notifyListeners();
    }
  }

  void toggleMute() {
    muted = !muted;
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> _poll() async {
    if (_polling || busy || _accepting) return;
    _polling = true;
    final revision = _revision;
    try {
      final uid = SupabaseService.currentUser?.id;
      if (uid != _sessionUser) {
        await _release();
        call = null;
        error = null;
        _pendingEnd = null;
        _sessionUser = uid;
        notifyListeners();
      }
      if (uid == null) return;
      if (_pendingEnd != null) {
        await action('end', id: _pendingEnd);
        _pendingEnd = null;
        if (error == 'Call ended on this device. Waiting to notify your peer.') {
          error = null;
        }
      }
      final current = await action('sync');
      if (revision != _revision) return;
      if (!active && current != null && current['id'] != call?['id']) {
        call = current;
        error = null;
        notifyListeners();
      }
      if (!active) return;
      final latest = await SupabaseService.client
          .from('voice_calls')
          .select()
          .eq('id', call!['id'] as String)
          .single();
      if (revision != _revision) return;
      call = Map<String, dynamic>.from(latest);
      if (!active) {
        await _release();
        notifyListeners();
        return;
      }
      if (DateTime.now().difference(_lastBeat).inSeconds >= 10) {
        await action('heartbeat');
        _lastBeat = DateTime.now();
      }
      if (revision != _revision) return;
      if (_pc != null) {
        final answer = call!['answer'];
        if (!_remoteSet && answer is Map) {
          await _pc!.setRemoteDescription(
            RTCSessionDescription(
              answer['sdp'] as String?,
              answer['type'] as String?,
            ),
          );
          _remoteSet = true;
        }
        while (_pendingIce.isNotEmpty) {
          await action('candidate', payload: _pendingIce.first);
          _pendingIce.removeAt(0);
        }
        if (_remoteSet) {
          final rows = await SupabaseService.client
              .from('voice_call_candidates')
              .select()
              .eq('call_id', call!['id'] as String)
              .neq('sender_id', uid)
              .order('id');
          for (final row in rows) {
            final id = (row['id'] as num).toInt();
            if (_receivedIce.contains(id)) continue;
            final ice = row['candidate'] as Map;
            await _pc!.addCandidate(
              RTCIceCandidate(
                ice['candidate'] as String?,
                ice['sdpMid'] as String?,
                ice['sdpMLineIndex'] as int?,
              ),
            );
            _receivedIce.add(id);
          }
        }
        if (_pc!.connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
            status != 'connected') {
          await action('connected');
        }
      }
      notifyListeners();
    } catch (e) {
      // Missing migration or offline idle client must not interrupt unrelated screens.
      if (active && revision == _revision) {
        error = message(e);
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _release() async {
    final pc = _pc;
    _pc = null;
    final local = _local;
    _local = null;
    final renderer = remoteAudio;
    remoteAudio = null;
    // Release the microphone even when native peer teardown throws.
    for (final track in local?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await track.stop();
      } catch (_) {
        debugPrint('Voice track cleanup failed');
      }
    }
    try {
      await local?.dispose();
    } catch (_) {
      debugPrint('Voice stream cleanup failed');
    }
    if (pc != null) {
      pc.onConnectionState = null;
      pc.onTrack = null;
      pc.onIceCandidate = null;
      try {
        await pc.close();
      } catch (_) {
        debugPrint('Voice connection close failed');
      }
      try {
        await pc.dispose();
      } catch (_) {
        debugPrint('Voice connection cleanup failed');
      }
    }
    try {
      await renderer?.dispose();
    } catch (_) {
      debugPrint('Voice output cleanup failed');
    }
    muted = false;
    _remoteSet = false;
    _pendingIce.clear();
    _receivedIce.clear();
  }

  void dismiss() {
    if (!active && !busy) {
      call = null;
      error = null;
      notifyListeners();
    }
  }
}
