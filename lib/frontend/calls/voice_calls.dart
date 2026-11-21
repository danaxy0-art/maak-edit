import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../backend/calls/voice_call_service.dart';
import '../../backend/services/supabase_service.dart';

const voiceIssueCategories = [
  'No audio',
  'Poor audio',
  'Disconnected',
  'Could not connect',
  'Other',
];

/// A root overlay keeps incoming/ongoing calls available from every screen.
class VoiceCallHost extends StatefulWidget {
  final Widget child;
  const VoiceCallHost({super.key, required this.child});
  @override
  State<VoiceCallHost> createState() => _VoiceCallHostState();
}

class _VoiceCallHostState extends State<VoiceCallHost> {
  final service = VoiceCallService.instance;
  final callNavigator = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    service.startWatching();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) => Stack(
      children: [
        widget.child,
        if (service.call != null || service.busy)
          Positioned.fill(
            child: Material(
              child: HeroControllerScope.none(
                child: Navigator(
                  key: callNavigator,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => AnimatedBuilder(
                      animation: service,
                      builder: (context, _) =>
                          SafeArea(child: _CallPanel(service: service)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _CallPanel extends StatelessWidget {
  final VoiceCallService service;
  const _CallPanel({required this.service});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Private voice call')),
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
            const Text(
              'Voice call with your connected peer',
              textAlign: TextAlign.center,
            ),
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
          const Text(
            'Recurring problems in loaded reports',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 8,
            children: voiceIssueCategories
                .map(
                  (c) => Chip(
                    label: Text(
                      '$c: ${all.where((r) => r["category"] == c).length}',
                    ),
                  ),
                )
                .toList(),
          ),
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
