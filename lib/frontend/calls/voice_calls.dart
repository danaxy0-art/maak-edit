import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../backend/calls/call_ringer.dart';
import '../../backend/calls/voice_call_service.dart';
import '../../backend/services/supabase_service.dart';
import '../design/components.dart' show SoftCard, IconBadge;
import '../design/tokens.dart';

const voiceIssueCategories = [
  'No audio',
  'Poor audio',
  'Disconnected',
  'Could not connect',
  'Other',
];

/// Keeps incoming and ongoing calls available from every screen without
/// blocking the app:
/// * an incoming call is a banner at the top (Accept / Decline) that rings
///   while the app is open; the rest of the app stays usable, and the banner
///   can be shrunk to a small pill;
/// * an ongoing call opens full screen and can be minimised to a bar at the
///   top ("Tap to return");
/// * an incoming call that ends unanswered just disappears (the server sends
///   a "Missed voice call" notification).
/// With the app closed, the server's push rings the phone instead
/// (20261127030000_voice_call_ringing.sql, send-push 'maak_calls' channel).
class VoiceCallHost extends StatefulWidget {
  final Widget child;
  const VoiceCallHost({super.key, required this.child});
  @override
  State<VoiceCallHost> createState() => _VoiceCallHostState();
}

class _VoiceCallHostState extends State<VoiceCallHost> {
  final service = VoiceCallService.instance;
  final callNavigator = GlobalKey<NavigatorState>();
  String? _callId;
  bool _minimized = false;
  bool _bannerCollapsed = false;
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    service.startWatching();
    service.addListener(_onCallChanged);
  }

  @override
  void dispose() {
    service.removeListener(_onCallChanged);
    CallRinger.stop();
    super.dispose();
  }

  String? get _me => SupabaseService.currentUser?.id;

  String? get _peerId {
    final call = service.call;
    if (call == null) return null;
    return call['caller_id'] == _me
        ? call['callee_id'] as String?
        : call['caller_id'] as String?;
  }

  String get _peerName => _names[_peerId] ?? 'Your connected peer';

  void _onCallChanged() {
    final call = service.call;
    final id = call?['id'] as String?;
    if (id != _callId) {
      _callId = id;
      if (mounted) {
        setState(() {
          _minimized = false;
          _bannerCollapsed = false;
        });
      }
      _loadPeerName();
    }
    if (service.incoming && !service.busy) {
      CallRinger.start(id!);
    } else {
      CallRinger.stop();
      // Answered, declined or over: the ringing push is no longer needed.
      final requestId = call?['request_id'] as String?;
      if (requestId != null) CallRinger.clearPush(requestId);
    }
    // An incoming call that ended without an answer has nothing to show.
    if (call != null &&
        !service.active &&
        !service.busy &&
        call['callee_id'] == _me &&
        call['accepted_at'] == null) {
      scheduleMicrotask(service.dismiss);
    }
    // Show how a call I took part in ended, even if it was minimised.
    if (call != null && !service.active && _minimized && mounted) {
      setState(() => _minimized = false);
    }
  }

  Future<void> _loadPeerName() async {
    final peer = _peerId;
    if (peer == null || _names.containsKey(peer)) return;
    try {
      final profile = await SupabaseService.client.rpc(
        'get_maak_member_profile',
        params: {'p_user_id': peer},
      );
      final name = (profile as Map)['full_name']?.toString();
      if (name != null && name.isNotEmpty && mounted) {
        setState(() => _names[peer] = name);
      }
    } catch (_) {
      // Keeps the generic label.
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) {
      final call = service.call;
      final incoming = service.incoming && !service.busy;
      final ongoing = service.active && !service.incoming;
      final showPanel =
          !incoming && (service.busy || call != null) && !(_minimized && ongoing);
      return Stack(
        children: [
          widget.child,
          if (showPanel)
            Positioned.fill(
              child: Material(
                child: HeroControllerScope.none(
                  child: Navigator(
                    key: callNavigator,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => AnimatedBuilder(
                        animation: service,
                        builder: (context, _) => SafeArea(
                          child: _CallPanel(
                            service: service,
                            peerName: _peerName,
                            onMinimize: service.active && !service.busy
                                ? () => setState(() => _minimized = true)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (incoming)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _IncomingCallBanner(
                  name: _peerName,
                  collapsed: _bannerCollapsed,
                  onAccept: service.accept,
                  onDecline: () => service.end(reject: true),
                  onToggle: () =>
                      setState(() => _bannerCollapsed = !_bannerCollapsed),
                ),
              ),
            ),
          if (_minimized && ongoing && !service.busy)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _OngoingCallBar(
                  service: service,
                  name: _peerName,
                  onOpen: () => setState(() => _minimized = false),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Non-blocking incoming call: the app underneath stays usable.
class _IncomingCallBanner extends StatelessWidget {
  final String name;
  final bool collapsed;
  final VoidCallback onAccept, onDecline, onToggle;
  const _IncomingCallBanner({
    required this.name,
    required this.collapsed,
    required this.onAccept,
    required this.onDecline,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // No tooltips here: this sits above the app's Navigator (no Overlay).
    final accept = Semantics(
      button: true,
      label: 'Accept call from $name',
      excludeSemantics: true,
      child: FilledButton.icon(
        onPressed: onAccept,
        style: FilledButton.styleFrom(backgroundColor: MaakColors.success),
        icon: const Icon(Icons.call, size: 18),
        label: const Text('Accept'),
      ),
    );
    final decline = Semantics(
      button: true,
      label: 'Decline call from $name',
      excludeSemantics: true,
      child: FilledButton.icon(
        onPressed: onDecline,
        style: FilledButton.styleFrom(backgroundColor: MaakColors.error),
        icon: const Icon(Icons.call_end, size: 18),
        label: const Text('Decline'),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: 'Incoming voice call from $name',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: MaakColors.button,
          elevation: 8,
          borderRadius: BorderRadius.circular(collapsed ? 28 : 20),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: collapsed
                ? InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.ring_volume, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Incoming call · $name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _RoundCallButton(
                            icon: Icons.call_end,
                            color: MaakColors.error,
                            label: 'Decline call from $name',
                            onPressed: onDecline,
                          ),
                          const SizedBox(width: 6),
                          _RoundCallButton(
                            icon: Icons.call,
                            color: MaakColors.success,
                            label: 'Accept call from $name',
                            onPressed: onAccept,
                          ),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 20,
                              backgroundColor: Color(0xFFFAD8D2),
                              child: Icon(Icons.call, color: Color(0xFFCE737C)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Incoming voice call',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: 'Make smaller',
                              excludeSemantics: true,
                              child: IconButton(
                                onPressed: onToggle,
                                icon: const Icon(
                                  Icons.keyboard_arrow_up,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: decline),
                            const SizedBox(width: 10),
                            Expanded(child: accept),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;
  const _RoundCallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    ),
  );
}

/// A minimised ongoing call: tap to return to it.
class _OngoingCallBar extends StatelessWidget {
  final VoiceCallService service;
  final String name;
  final VoidCallback onOpen;
  const _OngoingCallBar({
    required this.service,
    required this.name,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final connectedAt = DateTime.tryParse(
      '${service.call?['connected_at'] ?? ''}',
    );
    String status = service.statusLabel;
    if (service.status == 'connected' && connectedAt != null) {
      final d = DateTime.now().difference(connectedAt.toLocal());
      final m = d.inMinutes.toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      status = '$m:$s';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: MaakColors.success,
        elevation: 6,
        borderRadius: BorderRadius.circular(28),
        child: Semantics(
          button: true,
          label: 'Voice call with $name, $status. Tap to return to the call',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              child: Row(
                children: [
                  Icon(
                    service.muted ? Icons.mic_off : Icons.call,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$name · $status · Tap to return',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _RoundCallButton(
                    icon: Icons.call_end,
                    color: MaakColors.error,
                    label: 'End call',
                    onPressed: service.end,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallPanel extends StatelessWidget {
  final VoiceCallService service;
  final String peerName;

  /// Shrinks an ongoing call to the bar at the top; null when not possible.
  final VoidCallback? onMinimize;
  const _CallPanel({
    required this.service,
    required this.peerName,
    this.onMinimize,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: onMinimize == null
          ? null
          : IconButton(
              tooltip: 'Minimise call',
              onPressed: onMinimize,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
      title: const Text('Private voice call'),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFFFAD8D2),
              child: Icon(Icons.call, size: 44, color: Color(0xFFCE737C)),
            ),
            const SizedBox(height: 24),
            Text(
              service.statusLabel,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('Voice call with $peerName', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Peer support is not medical advice.',
              textAlign: TextAlign.center,
            ),
            if (service.call?['connected_at'] != null)
              Text(
                'Connected at ${DateTime.parse(service.call!["connected_at"] as String).toLocal().toString().substring(11, 19)}',
              ),
            if (service.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  service.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (service.remoteAudio != null)
              SizedBox(
                width: 1,
                height: 1,
                child: RTCVideoView(service.remoteAudio!),
              ),
            const SizedBox(height: 24),
            if (service.busy)
              const CircularProgressIndicator()
            else if (service.incoming)
              Wrap(
                spacing: 16,
                children: [
                  FilledButton.icon(
                    onPressed: service.accept,
                    icon: const Icon(Icons.call),
                    label: const Text('Accept'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => service.end(reject: true),
                    icon: const Icon(Icons.call_end),
                    label: const Text('Reject'),
                  ),
                ],
              )
            else if (service.active)
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (service.status == 'connected')
                    OutlinedButton.icon(
                      onPressed: service.toggleMute,
                      icon: Icon(service.muted ? Icons.mic_off : Icons.mic),
                      label: Text(service.muted ? 'Unmute' : 'Mute'),
                    ),
                  FilledButton.icon(
                    onPressed: service.end,
                    icon: const Icon(Icons.call_end),
                    label: const Text('End call'),
                  ),
                  if (onMinimize != null)
                    TextButton.icon(
                      onPressed: onMinimize,
                      icon: const Icon(Icons.open_in_full, size: 18),
                      label: const Text('Use the app during the call'),
                    ),
                ],
              )
            else
              FilledButton(
                onPressed: service.dismiss,
                child: const Text('Close'),
              ),
            if (service.call != null && !service.busy)
              TextButton.icon(
                onPressed: () =>
                    reportVoiceIssue(context, service.call!['id'] as String),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report a technical issue'),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> reportVoiceIssue(BuildContext context, String callId) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ReportVoiceDialog(callId: callId),
  );
}

class _ReportVoiceDialog extends StatefulWidget {
  final String callId;
  const _ReportVoiceDialog({required this.callId});
  @override
  State<_ReportVoiceDialog> createState() => _ReportVoiceDialogState();
}

class _ReportVoiceDialogState extends State<_ReportVoiceDialog> {
  final text = TextEditingController();
  String category = voiceIssueCategories.first;
  String? error;
  bool busy = false, sent = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (text.text.trim().length < 10) {
      setState(
        () => error = 'Please describe the issue in at least 10 characters.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SupabaseService.client.rpc(
        'report_voice_call',
        params: {
          'p_call_id': widget.callId,
          'p_category': category,
          'p_description': text.text.trim(),
        },
      );
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = VoiceCallService.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(sent ? 'Report submitted' : 'Report a call issue'),
    content: sent
        ? const Text('Your technical issue was sent to the Admin for review.')
        : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Describe the technical problem. Do not include private conversation details.',
                ),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: voiceIssueCategories
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => category = v!),
                ),
                TextField(
                  controller: text,
                  maxLength: 2000,
                  maxLines: 4,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'What happened?',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
    actions: sent
        ? [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ]
        : [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Sending…' : 'Submit'),
            ),
          ],
  );
}

class VoiceCallHistoryPage extends StatefulWidget {
  final String requestId;
  const VoiceCallHistoryPage({super.key, required this.requestId});
  @override
  State<VoiceCallHistoryPage> createState() => _VoiceCallHistoryPageState();
}

class _VoiceCallHistoryPageState extends State<VoiceCallHistoryPage> {
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<Map<String, dynamic>>> load() async {
    await VoiceCallService.instance.action('sync');
    return await SupabaseService.client
        .from('voice_calls')
        .select(
          'id,caller_id,status,created_at,end_reason,connected_at,ended_at',
        )
        .eq('request_id', widget.requestId)
        .order('created_at', ascending: false)
        .limit(100);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Voice call history'),
      actions: [
        IconButton(
          onPressed: () => setState(() => future = load()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => future = load()),
              child: const Text('Could not load calls. Retry'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) {
          return const Center(child: Text('No voice calls yet.'));
        }
        return ListView(
          children: s.data!
              .map(
                (c) => ListTile(
                  leading: Icon(
                    c['caller_id'] == SupabaseService.userId
                        ? Icons.call_made
                        : Icons.call_received,
                  ),
                  title: Text(
                    '${c["status"].toString().toUpperCase()}${c["end_reason"] == "rejected" ? " · Rejected" : ""}',
                  ),
                  subtitle: Text(
                    DateTime.parse(
                      c['created_at'] as String,
                    ).toLocal().toString().split('.').first,
                  ),
                  trailing: IconButton(
                    tooltip: 'Report technical issue',
                    icon: const Icon(Icons.flag_outlined),
                    onPressed: () =>
                        reportVoiceIssue(context, c['id'] as String),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class AdminVoiceCallIssuesPage extends StatefulWidget {
  final bool embedded;
  const AdminVoiceCallIssuesPage({super.key, this.embedded = false});
  @override
  State<AdminVoiceCallIssuesPage> createState() =>
      _AdminVoiceCallIssuesPageState();
}

class _AdminVoiceCallIssuesPageState extends State<AdminVoiceCallIssuesPage> {
  late Future<List<Map<String, dynamic>>> future;
  String filter = 'all';
  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<Map<String, dynamic>>> load() async => await SupabaseService
      .client
      .from('voice_call_issues')
      .select()
      .order('created_at', ascending: false);
  Future<void> review(Map<String, dynamic> issue) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReviewVoiceDialog(issue: issue),
    );
    if (mounted) setState(() => future = load());
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? _body()
      : Scaffold(
          appBar: AppBar(title: const Text('Voice call reports')),
          body: _body(),
        );

  Widget _body() => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, s) {
      if (s.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(() => future = load()),
            child: const Text('Could not load issues. Retry'),
          ),
        );
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final all = s.data!;
      final rows = all.where((r) => filter == 'all' || r['status'] == filter);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${all.where((r) => r['status'] == 'open').length} call reports need review',
                ),
              ),
              IconButton(
                tooltip: 'Refresh call reports',
                onPressed: () => setState(() => future = load()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Recurring problems in loaded reports',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _ProblemStats(reports: all),
          const SizedBox(height: 16),
          DropdownButton<String>(
            value: filter,
            items: [
              'all',
              'open',
              'reviewing',
              'resolved',
              'dismissed',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => filter = v!),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No issues in this category.'),
            ),
          ...rows.map(
            (r) => Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFAD8D2),
                  child: Icon(
                    Icons.phone_in_talk_outlined,
                    color: Color(0xFF9B535C),
                  ),
                ),
                title: Text('${r["category"]} · ${r["status"]}'),
                subtitle: Text(
                  '${r["description"]}\nCall: ${r["call_id"]}\nReported: ${r["created_at"]}${r["admin_note"] == null ? "" : "\nAdmin note: ${r["admin_note"]}"}',
                ),
                isThreeLine: true,
                onTap: () => review(r),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ReviewVoiceDialog extends StatefulWidget {
  final Map<String, dynamic> issue;
  const _ReviewVoiceDialog({required this.issue});
  @override
  State<_ReviewVoiceDialog> createState() => _ReviewVoiceDialogState();
}

class _ReviewVoiceDialogState extends State<_ReviewVoiceDialog> {
  final note = TextEditingController();
  String status = 'reviewing';
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    note.text = widget.issue['admin_note'] as String? ?? '';
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (note.text.trim().length < 3) {
      setState(() => error = 'Add a review note (at least 3 characters).');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SupabaseService.client.rpc(
        'review_voice_call_issue',
        params: {
          'p_issue_id': widget.issue['id'],
          'p_status': status,
          'p_note': note.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = VoiceCallService.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review technical issue'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.issue['description'] as String),
          DropdownButtonFormField<String>(
            initialValue: status,
            items: [
              'reviewing',
              'resolved',
              'dismissed',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: busy ? null : (v) => setState(() => status = v!),
          ),
          TextField(
            controller: note,
            maxLength: 2000,
            maxLines: 3,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Admin review note'),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: const Text('Save review'),
      ),
    ],
  );
}

/// One equal-size compact tile per problem category, in a fixed grid
/// (3 columns on phones, all 5 in a row from 560 px wide).
class _ProblemStats extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  const _ProblemStats({required this.reports});

  static const _icons = {
    'No audio': Icons.volume_off_outlined,
    'Poor audio': Icons.graphic_eq,
    'Disconnected': Icons.call_end_outlined,
    'Could not connect': Icons.signal_cellular_connected_no_internet_4_bar,
    'Other': Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      final width = constraints.maxWidth;
      final columns = width >= 560 ? 5 : 3;
      final tileWidth = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final category in voiceIssueCategories)
            SizedBox(
              width: tileWidth,
              height: 84,
              child: _tile(
                category,
                reports.where((r) => r['category'] == category).length,
              ),
            ),
        ],
      );
    },
  );

  Widget _tile(String label, int count) => Semantics(
    label: '$label: $count reports',
    excludeSemantics: true,
    child: SoftCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            _icons[label] ?? Icons.report_problem_outlined,
            size: 24,
            color: count > 0 ? MaakColors.blush : MaakColors.fill,
          ),
          const Spacer(),
          // One line in every tile: a long label shrinks rather than wraps.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 11, color: MaakColors.muted),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 18,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: MaakColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}
