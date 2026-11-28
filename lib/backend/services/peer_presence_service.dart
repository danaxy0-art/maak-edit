import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PeerPresenceStatus {
  checking,
  online,
  offline,
}

class PeerPresenceService {
  PeerPresenceService._();

  static final instance = PeerPresenceService._();

  final _supabase = Supabase.instance.client;

  final Map<String, _PresenceEntry> _entries = {};

  ValueNotifier<PeerPresenceStatus> acquire(String userId) {
    final existing = _entries[userId];

    if (existing != null) {
      existing.references++;
      return existing.status;
    }

    final channel = _supabase.channel(
      'presence:$userId',
      opts: const RealtimeChannelConfig(private: true),
    );

    final entry = _PresenceEntry(channel);
    _entries[userId] = entry;

    channel.onPresenceSync((payload) {
      if (_entries[userId] != entry) return;

      entry.status.value = channel.presenceState().isNotEmpty
          ? PeerPresenceStatus.online
          : PeerPresenceStatus.offline;
    });

    channel.subscribe((status, error) {
      if (_entries[userId] != entry) return;

      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        entry.status.value = PeerPresenceStatus.checking;
      }
    });

    return entry.status;
  }

  void release(String userId) {
    final entry = _entries[userId];

    if (entry == null) return;

    entry.references--;

    if (entry.references > 0) return;

    _entries.remove(userId);
    _supabase.removeChannel(entry.channel);
    entry.status.dispose();
  }
}

class _PresenceEntry {
  final RealtimeChannel channel;

  final status = ValueNotifier<PeerPresenceStatus>(
    PeerPresenceStatus.checking,
  );

  int references = 1;

  _PresenceEntry(this.channel);
}