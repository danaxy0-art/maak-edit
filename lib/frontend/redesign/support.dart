import '../../backend/models/message_order.dart';
import 'matching_page.dart';
import 'app_text_field.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'feedback.dart';

class DataListPage extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback) item;
  final String emptyTitle, emptyText;
  final Widget? header;
  final Widget Function(VoidCallback)? headerBuilder;
  const DataListPage({
    super.key,
    required this.title,
    required this.load,
    required this.item,
    this.emptyTitle = 'Nothing here yet',
    this.emptyText = 'Your activity will appear here.',
    this.header,
    this.headerBuilder,
  });
  @override
  State<DataListPage> createState() => _DataListPageState();
}

class _DataListPageState extends State<DataListPage> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = widget.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ResponsiveBody(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, s) {
          if (s.hasError) {
            return EmptyState(
              'Could not load data',
              friendlyError(s.error!),
              retry: _reload,
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.header != null) widget.header!,
                if (widget.headerBuilder != null)
                  widget.headerBuilder!(_reload),
                if (s.data!.isEmpty)
                  EmptyState(widget.emptyTitle, widget.emptyText),
                for (final row in s.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: widget.item(context, row, _reload),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class VolunteerDirectoryPage extends StatefulWidget {
  const VolunteerDirectoryPage({super.key});
  @override
  State<VolunteerDirectoryPage> createState() => _VolunteerDirectoryPageState();
}

class _VolunteerDirectoryPageState extends State<VolunteerDirectoryPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String _search = '';
  @override
  void initState() {
    super.initState();
    _future = SupabaseService.getVolunteers();
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(
      title: const Text('Find a volunteer'),
      actions: [
        IconButton(
          tooltip: 'Recommended matches',
          icon: const Icon(Icons.auto_awesome),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MatchingPage()),
          ),
        ),
      ],
    ),
    body: ResponsiveBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              maxLength: 100,
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search name, condition or language',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, s) {
                if (s.hasError) {
                  return EmptyState(
                    'Could not load volunteers',
                    friendlyError(s.error!),
                    retry: () => setState(
                      () => _future = SupabaseService.getVolunteers(),
                    ),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = s.data!
                    .where(
                      (r) =>
                          '${r['full_name']} ${r['condition']} ${r['language']}'
                              .toLowerCase()
                              .contains(_search),
                    )
                    .toList();
                if (rows.isEmpty) {
                  return const EmptyState(
                    'No volunteers found',
                    'Try another search or check again later.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SurfaceCard(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  VolunteerDetailPage(volunteer: row),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 25,
                                backgroundColor: AppColors.selectedCardFill,
                                child: Text(
                                  initials(row['full_name'] as String? ?? 'V'),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['full_name'] as String? ??
                                          'Volunteer',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      '${row['condition']} · ${row['language']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class VolunteerDetailPage extends StatefulWidget {
  final Map<String, dynamic> volunteer;
  const VolunteerDetailPage({super.key, required this.volunteer});
  @override
  State<VolunteerDetailPage> createState() => _VolunteerDetailPageState();
}

class _VolunteerDetailPageState extends State<VolunteerDetailPage> {
  bool _busy = false, _sent = false;
  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      await SupabaseService.requestSupport(
        widget.volunteer['user_id'] as String,
      );
      if (mounted) {
        setState(() => _sent = true);
        showSuccess(context, 'Support request sent.');
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Volunteer profile')),
    body: ResponsiveBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 45,
              backgroundColor: AppColors.selectedCardFill,
              child: Text(
                initials(widget.volunteer['full_name'] as String? ?? ''),
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.volunteer['full_name'] as String? ?? 'Volunteer',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'MaakSerif',
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: RoleChip('Approved volunteer')),
          const SectionTitle('Lived experience'),
          SurfaceCard(
            child: Text(
              widget.volunteer['description'] as String? ?? '',
              style: const TextStyle(height: 1.6),
            ),
          ),
          const SectionTitle('Support preferences'),
          SurfaceCard(
            child: Text(
              '${widget.volunteer['condition']}\n${widget.volunteer['language']}',
              style: const TextStyle(height: 1.8),
            ),
          ),
          const SizedBox(height: 26),
          PrimaryButton(
            _sent ? 'Request sent' : 'Request support',
            busy: _busy,
            onPressed: _sent ? null : _request,
          ),
        ],
      ),
    ),
  );
}

class RequestsPage extends StatelessWidget {
  const RequestsPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Support requests',
    load: SupabaseService.getRequests,
    emptyTitle: 'No requests yet',
    emptyText: 'New help seeker requests will appear here.',
    item: (context, row, refresh) => SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row['contact_name'] as String? ?? 'Help seeker',
            style: const TextStyle(
              fontFamily: 'MaakSerif',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            row['condition'] as String? ?? '',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if ((row['description'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(row['description'] as String),
            ),
          const SizedBox(height: 12),
          RoleChip(row['status'] as String),
          if (row['status'] == 'pending')
            RequestDecisionButtons(
              key: ValueKey(row['id']),
              requestId: row['id'] as String,
              onSaved: refresh,
            ),
          if (row['status'] == 'accepted') ...[
            const SizedBox(height: 12),
            PrimaryButton(
              'Open conversation',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConversationPage(
                    requestId: row['id'] as String,
                    name: row['contact_name'] as String? ?? 'Your peer',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class RequestDecisionButtons extends StatefulWidget {
  final String requestId;
  final VoidCallback onSaved;
  const RequestDecisionButtons({
    super.key,
    required this.requestId,
    required this.onSaved,
  });
  @override
  State<RequestDecisionButtons> createState() => _RequestDecisionButtonsState();
}

class _RequestDecisionButtonsState extends State<RequestDecisionButtons> {
  bool _busy = false, _saved = false;
  Future<void> _decide(bool accept) async {
    if (_busy || _saved) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.decideRequest(widget.requestId, accept);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showAppError(context, e);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _saved = true;
      _busy = false;
    });
    showSuccess(
      context,
      accept ? 'Support request accepted.' : 'Support request declined.',
    );
    // The decision has committed. A refresh failure must not offer to repeat it.
    try {
      widget.onSaved();
    } catch (_) {
      if (mounted)
        showSuccess(
          context,
          'Decision saved. Reopen this page to refresh the list.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy || _saved ? null : () => _decide(false),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PrimaryButton(
            'Accept',
            busy: _busy,
            onPressed: _busy || _saved ? null : () => _decide(true),
          ),
        ),
      ],
    ),
  );
}

class ConversationsPage extends StatelessWidget {
  const ConversationsPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Messages',
    load: () async => (await SupabaseService.getRequests())
        .where((r) => r['status'] == 'accepted')
        .toList(),
    emptyTitle: 'Start a connection',
    emptyText: 'Accepted support requests become conversations here.',
    item: (context, row, reload) => SurfaceCard(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConversationPage(
              requestId: row['id'] as String,
              name: row['contact_name'] as String? ?? 'Your peer',
            ),
          ),
        );
        reload();
      },
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.selectedCardFill,
            child: Text(initials(row['contact_name'] as String? ?? 'Peer')),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['contact_name'] as String? ?? 'Your peer',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                Text(
                  row['last_message'] as String? ?? 'Say hello to your peer.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}

class ConversationPage extends StatefulWidget {
  final String requestId, name;
  const ConversationPage({
    super.key,
    required this.requestId,
    required this.name,
  });
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _lastMessageId;
  bool _reading = false;
  late Stream<List<Map<String, dynamic>>> _stream;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = SupabaseService.messageStream(widget.requestId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final text = _input.text;
    try {
      await SupabaseService.sendMessage(widget.requestId, text);
      if (mounted && _input.text == text) _input.clear();
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: ResponsiveBody(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.selectedCardFill,
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Peer support is not medical advice.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, s) {
                if (s.hasError) {
                  return EmptyState(
                    'Could not load conversation',
                    friendlyError(s.error!),
                    retry: () => setState(
                      () => _stream = SupabaseService.messageStream(
                        widget.requestId,
                      ),
                    ),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.data!.isEmpty) {
                  return const EmptyState(
                    'Say hello',
                    'Start your conversation with a kind message.',
                    icon: Icons.chat_bubble_outline,
                  );
                }
                final messages = chronologicalMessages(s.data!);
                final last = messages.last['id'] as String;
                final nearBottom =
                    !_scroll.hasClients || _scroll.position.extentAfter < 100;
                if (_lastMessageId != last) {
                  _lastMessageId = last;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _scroll.hasClients && nearBottom)
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  });
                }
                final unread = messages
                    .where(
                      (m) =>
                          m['sender_id'] != SupabaseService.userId &&
                          m['read_at'] == null,
                    )
                    .map((m) => m['id'] as String)
                    .toList();
                if (!_reading &&
                    unread.isNotEmpty &&
                    ModalRoute.of(context)?.isCurrent == true &&
                    WidgetsBinding.instance.lifecycleState ==
                        AppLifecycleState.resumed) {
                  _reading = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    try {
                      if (mounted && ModalRoute.of(context)?.isCurrent == true)
                        await SupabaseService.markMessagesRead(
                          widget.requestId,
                          unread,
                        );
                    } catch (_) {
                      // Keep unread counts intact if acknowledgement fails.
                    } finally {
                      _reading = false;
                    }
                  });
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: false,
                  padding: const EdgeInsets.all(18),
                  itemCount: s.data!.length,
                  itemBuilder: (context, i) {
                    final m = messages[i],
                        me = m['sender_id'] == SupabaseService.userId;
                    return Align(
                      alignment: me
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .72,
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: me ? AppColors.primaryNavy : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          m['body'] as String,
                          style: TextStyle(
                            color: me ? Colors.white : AppColors.textDark,
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a message...',
                      ),
                      enabled: !_busy,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    tooltip: 'Send message',
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class JourneyPage extends StatelessWidget {
  const JourneyPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'My journey',
    load: SupabaseService.getRequests,
    emptyTitle: 'Your journey starts here',
    emptyText: 'Find a volunteer to take the next step.',
    item: (context, row, reload) => SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row['contact_name'] as String? ?? 'Volunteer',
            style: const TextStyle(
              fontFamily: 'MaakSerif',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          RoleChip(
            row['status'] == 'pending'
                ? 'Awaiting response'
                : row['status'] == 'accepted'
                ? 'Connected'
                //اضافه جديده عشان ال كانسل  لما يطلب
                : row['status'] == 'canceled'
                ? 'Canceled'
                //الى هنا
                : 'Declined',
          ),
          const SizedBox(height: 14),
          Text(
            row['status'] == 'accepted'
                ? 'You can now message your volunteer.'
                : 'Your support request has been recorded.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          // اضافه جديده بعد
          if (row['status'] == 'pending')
            CancelRequestButton(
              requestId: row['id'] as String,
              onDone: reload,
            ), // هنا تنتهي
          if (row['status'] == 'accepted')
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConversationPage(
                    requestId: row['id'] as String,
                    name: row['contact_name'] as String? ?? 'Volunteer',
                  ),
                ),
              ),
              child: const Text('Open conversation'),
            ),
        ],
      ),
    ),
  );
}
// اضافه جديده

class CancelRequestButton extends StatefulWidget {
  final String requestId;
  final VoidCallback onDone;
  const CancelRequestButton({
    super.key,
    required this.requestId,
    required this.onDone,
  });
  @override
  State<CancelRequestButton> createState() => _CancelRequestButtonState();
}

class _CancelRequestButtonState extends State<CancelRequestButton> {
  bool _busy = false;
  Future<void> _cancel() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text('The volunteer will be notified.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await SupabaseService.cancelRequest(widget.requestId);
      if (!mounted) return;
      showSuccess(context, 'Request canceled.');
      widget.onDone();
    } catch (e) {
      if (mounted) showAppError(context, e, retry: _cancel);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: _busy ? null : _cancel,
    child: Text(_busy ? 'Canceling...' : 'Cancel request'),
  );
}
// هنا تنتهي

class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Resources',
    load: SupabaseService.getResources,
    emptyTitle: 'No resources published yet',
    emptyText: 'Resources added by your team will appear here.',
    item: (context, row, reload) => SurfaceCard(
      onTap: () async {
        try {
          final url = Uri.tryParse(row['url'] as String);
          if (url == null || url.scheme != 'https') {
            throw ArgumentError('Invalid resource link.');
          }
          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
            throw StateError('Could not open link');
          }
        } catch (e) {
          if (context.mounted) showAppError(context, e);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.description_outlined, color: AppColors.primaryNavy),
          const SizedBox(height: 12),
          Text(
            row['title'] as String,
            style: const TextStyle(
              fontFamily: 'MaakSerif',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            row['summary'] as String,
            style: const TextStyle(color: AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Read resource →',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

String formatDate(String date) {
  final d = DateTime.parse(date).toLocal();
  final minutes = d.minute.toString().padLeft(2, '0');
  final hour = d.hour == 0
      ? 12
      : d.hour > 12
      ? d.hour - 12
      : d.hour;
  return '${d.day}/${d.month}/${d.year} · $hour:$minutes ${d.hour >= 12 ? 'PM' : 'AM'}';
}
