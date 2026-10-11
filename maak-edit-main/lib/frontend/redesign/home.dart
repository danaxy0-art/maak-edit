import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../widgets/current_user_name.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'notifications.dart';
import 'navigation.dart';
import 'support.dart';
import 'feedback.dart';

class HomePage extends StatefulWidget {
  final String role;
  const HomePage({super.key, required this.role});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<List<Map<String, dynamic>>>> _future;
  bool get volunteer => widget.role == 'volunteer';
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = Future.wait([
    SupabaseService.getRequests(),
    SupabaseService.getSessions(),
  ]);
  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    body: SafeArea(
      child: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const LogoHeader(trailing: NotificationBell()),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: CurrentUserName(
                      prefix: 'Hello, ',
                      style: TextStyle(
                        fontFamily: 'MaakSerif',
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (volunteer) const RoleChip('Volunteer'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                volunteer
                    ? 'Thank you for being here.'
                    : 'You’re not alone on this journey.',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              HeroCard(
                title: volunteer
                    ? 'Your experience can make a difference.'
                    : 'Support from someone who understands.',
                subtitle: volunteer
                    ? 'Be there for someone who understands.'
                    : 'Connect with a volunteer who has a similar experience.',
                button: volunteer ? null : 'Find a volunteer',
                onTap: () => _push(const VolunteerDirectoryPage()),
              ),
              if (!volunteer) ...[
                const SectionTitle('Quick actions'),
                _quickActions(),
              ],
              FutureBuilder<List<List<Map<String, dynamic>>>>(
                future: _future,
                builder: (context, s) {
                  if (s.hasError) {
                    return EmptyState(
                      'Could not load your activity',
                      friendlyError(s.error!),
                      retry: () => setState(_load),
                    );
                  }
                  if (!s.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(22),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final requests = s.data![0], sessions = s.data![1];
                  final upcoming = sessions
                      .where(
                        (r) => DateTime.parse(
                          r['starts_at'] as String,
                        ).isAfter(DateTime.now()),
                      )
                      .toList();
                  final pending = requests
                      .where((r) => r['status'] == 'pending')
                      .length;
                  final accepted = requests
                      .where((r) => r['status'] == 'accepted')
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (volunteer) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _stat(
                                'Pending requests',
                                pending,
                                Icons.people_outline,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _stat(
                                'Upcoming sessions',
                                upcoming.length,
                                Icons.calendar_month_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(
                          'View requests',
                          icon: Icons.arrow_forward,
                          onPressed: () => _push(const RequestsPage()),
                        ),
                        const SectionTitle('Upcoming support session'),
                        if (upcoming.isEmpty)
                          const SurfaceCard(
                            child: Text(
                              'No upcoming sessions yet.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          )
                        else
                          SurfaceCard(
                            onTap: () =>
                                ShellScope.maybeOf(context)?.selectTab(1),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: AppColors.selectedCardFill,
                                  child: Icon(Icons.calendar_month_outlined),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        upcoming.first['contact_name']
                                                as String? ??
                                            'Your peer',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        formatDate(
                                          upcoming.first['starts_at'] as String,
                                        ),
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
                        const SectionTitle('Quick actions'),
                        _quickActions(),
                      ] else ...[
                        const SectionTitle('Recent conversation'),
                        if (accepted.isEmpty)
                          const SurfaceCard(
                            child: Text(
                              'Your conversations will appear here after a volunteer accepts your request.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                height: 1.4,
                              ),
                            ),
                          )
                        else
                          SurfaceCard(
                            onTap: () => _push(
                              ConversationPage(
                                requestId: accepted.first['id'] as String,
                                name:
                                    accepted.first['contact_name'] as String? ??
                                    'Volunteer',
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.selectedCardFill,
                                  child: Text(
                                    initials(
                                      accepted.first['contact_name']
                                              as String? ??
                                          'Peer',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        accepted.first['contact_name']
                                                as String? ??
                                            'Volunteer',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        accepted.first['last_message']
                                                as String? ??
                                            'Say hello and start your conversation.',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
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
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _stat(String title, int count, IconData icon) => SurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryNavy, size: 22),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Text(
          '$count',
          style: const TextStyle(
            fontFamily: 'MaakSerif',
            fontSize: 29,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
  Widget _quickActions() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _quick(
        volunteer ? 'Requests' : 'My journey',
        volunteer ? 'View and respond' : 'Track your progress',
        volunteer ? Icons.people_outline : Icons.book_outlined,
        () => volunteer
            ? _push(const RequestsPage())
            : ShellScope.maybeOf(context)?.selectTab(1),
      ),
      const SizedBox(width: 10),
      _quick(
        volunteer ? 'Schedule' : 'Messages',
        volunteer ? 'Manage your time' : 'Your conversations',
        volunteer ? Icons.calendar_month_outlined : Icons.chat_bubble_outline,
        () => ShellScope.maybeOf(context)?.selectTab(volunteer ? 1 : 2),
      ),
      const SizedBox(width: 10),
      _quick(
        volunteer ? 'Messages' : 'Resources',
        volunteer ? 'Your conversations' : 'Helpful information',
        volunteer ? Icons.chat_bubble_outline : Icons.description_outlined,
        () => volunteer
            ? ShellScope.maybeOf(context)?.selectTab(2)
            : _push(const ResourcesPage()),
      ),
    ],
  );
  Widget _quick(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => Expanded(
    child: SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.selectedCardFill,
            child: Icon(icon, size: 21),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    ),
  );
}
