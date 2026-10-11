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
    if (mounted) setState(() => _future = widget.load());
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
    appBar: AppBar(title: const Text('Find a volunteer')),
    body: ResponsiveBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
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
  bool _busy = false;
  Future<void> _decide(bool accept) async {
    setState(() => _busy = true);
    try {
      await SupabaseService.decideRequest(widget.requestId, accept);
      widget.onSaved();
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => _decide(false),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PrimaryButton(
            'Accept',
            busy: _busy,
            onPressed: () => _decide(true),
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

class _ConversationPageState extends State<ConversationPage> {
  final _input = TextEditingController();
  late Stream<List<Map<String, dynamic>>> _stream;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _stream = SupabaseService.messageStream(widget.requestId);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
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
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(18),
                  itemCount: s.data!.length,
                  itemBuilder: (context, i) {
                    final m = s.data![s.data!.length - 1 - i],
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
                        counterText: '',
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
                : 'Declined',
          ),
          const SizedBox(height: 14),
          Text(
            row['status'] == 'accepted'
                ? 'You can message your volunteer and view scheduled sessions.'
                : 'Your support request has been recorded.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (row['status'] == 'accepted')
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SchedulePage()),
              ),
              child: const Text('View sessions'),
            ),
        ],
      ),
    ),
  );
}

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});
  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Support sessions',
    load: SupabaseService.getSessions,
    headerBuilder: (refresh) => _ScheduleHeader(onScheduled: refresh),
    emptyTitle: 'No sessions scheduled',
    emptyText: 'Your upcoming sessions will appear here.',
    item: (context, row, reload) => SurfaceCard(
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.selectedCardFill,
            child: Icon(Icons.calendar_month_outlined),
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
                Text(formatDate(row['starts_at'] as String)),
                const SizedBox(height: 7),
                RoleChip(
                  DateTime.parse(
                        row['starts_at'] as String,
                      ).isBefore(DateTime.now())
                      ? 'Past session'
                      : 'Upcoming · 60 min',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ScheduleHeader extends StatelessWidget {
  final VoidCallback onScheduled;
  const _ScheduleHeader({required this.onScheduled});
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: SupabaseService.getMyRole(),
    builder: (context, s) => s.data != 'volunteer'
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: PrimaryButton(
              'Schedule a session',
              icon: Icons.add,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BookSessionPage()),
                );
                onScheduled();
              },
            ),
          ),
  );
}

class BookSessionPage extends StatefulWidget {
  const BookSessionPage({super.key});
  @override
  State<BookSessionPage> createState() => _BookSessionPageState();
}

class _BookSessionPageState extends State<BookSessionPage> {
  late final Future<List<Map<String, dynamic>>> _requests;
  String? _request;
  DateTime? _start;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _requests = SupabaseService.getRequests();
  }

  Future<void> _date() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null && mounted) {
      setState(
        () => _start = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_request == null || _start == null) {
      showAppError(context, ArgumentError('Choose a peer, date and time.'));
      return;
    }
    if (!_start!.isAfter(DateTime.now())) {
      showAppError(context, ArgumentError('Choose a future date and time.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await SupabaseService.bookSession(_request!, _start!);
      if (mounted) {
        showSuccess(context, 'Session scheduled.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Schedule a session')),
    body: ResponsiveBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const FieldLabel('Connected help seeker', requiredField: true),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _requests,
            builder: (context, s) {
              if (s.hasError) return Text(friendlyError(s.error!));
              if (!s.hasData) return const LinearProgressIndicator();
              final accepted = s.data!
                  .where((r) => r['status'] == 'accepted')
                  .toList();
              if (accepted.isEmpty) {
                return const EmptyState(
                  'No connected peers',
                  'Accept a support request first.',
                );
              }
              return AppSelectField<String>(
                initialValue: _request,
                hint: const Text('Select a help seeker'),
                isExpanded: true,
                items: accepted
                    .map(
                      (r) => DropdownMenuItem(
                        value: r['id'] as String,
                        child: Text(
                          r['contact_name'] as String? ?? 'Your peer',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _request = v),
              );
            },
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _busy ? null : _date,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              _start == null
                  ? 'Choose date and time'
                  : formatDate(_start!.toIso8601String()),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton('Confirm session', busy: _busy, onPressed: _save),
        ],
      ),
    ),
  );
}

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
