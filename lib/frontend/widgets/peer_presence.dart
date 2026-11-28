import 'package:flutter/material.dart';
import '../../backend/services/peer_presence_service.dart';

class PeerPresence extends StatefulWidget {
  final String userId;

  const PeerPresence({
    super.key,
    required this.userId,
  });

  @override
  State<PeerPresence> createState() => _PeerPresenceState();
}

class _PeerPresenceState extends State<PeerPresence> {
  final _service = PeerPresenceService.instance;

  late ValueNotifier<PeerPresenceStatus> _status;

  @override
  void initState() {
    super.initState();
    _status = _service.acquire(widget.userId);
  }

  @override
  void didUpdateWidget(covariant PeerPresence oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.userId != widget.userId) {
      _service.release(oldWidget.userId);
      _status = _service.acquire(widget.userId);
    }
  }

  @override
  void dispose() {
    _service.release(widget.userId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PeerPresenceStatus>(
      valueListenable: _status,
      builder: (context, status, child) {
        final online = status == PeerPresenceStatus.online;
        final checking = status == PeerPresenceStatus.checking;

        return Text(
          checking
              ? '● Checking...'
              : online
              ? '● Online'
              : '● Offline',
          style: TextStyle(
            color: online ? Colors.green : Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }
}