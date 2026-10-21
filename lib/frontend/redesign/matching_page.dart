import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import 'feedback.dart';
import 'support.dart';
import 'ui.dart';

class MatchingPage extends StatefulWidget {
  const MatchingPage({super.key});
  @override
  State<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends State<MatchingPage> {
  late Future<Map<String, dynamic>> _future;
  bool _useAi = false;
  @override
  void initState() {
    super.initState();
    _future = SupabaseService.getMatches();
  }

  void _reload() =>
      setState(() => _future = SupabaseService.getMatches(useAi: _useAi));
  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(
      title: const Text('Your volunteer matches'),
      actions: [
        IconButton(
          tooltip: 'Refresh matches',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ResponsiveBody(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Support that understands you',
            style: TextStyle(fontFamily: 'MaakSerif', fontSize: 26),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ConversationsPage(),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('View existing conversations'),
          ),
          const Text(
            'One shared condition is enough. Different volunteers can support you with different conditions.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _useAi,
            onChanged: (v) => setState(() => _useAi = v ?? false),
            title: const Text('Compare experiences with AI'),
            subtitle: const Text(
              'Optional: sends your support description and opted-in volunteers’ descriptions to Google Gemini. Names, emails and verification documents are not sent. Avoid identifying details in your description.',
            ),
          ),
          PrimaryButton(
            'Find matches',
            onPressed: _reload,
            icon: Icons.auto_awesome,
          ),
          const SizedBox(height: 20),
          FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, s) {
              if (s.hasError)
                return EmptyState(
                  'Could not load recommendations',
                  friendlyError(s.error!),
                  retry: _reload,
                );
              if (!s.hasData)
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: CircularProgressIndicator(),
                  ),
                );
              final data = s.data!;
              final matches = List<Map<String, dynamic>>.from(
                data['matches'] as List? ?? [],
              );
              final team = List<Map<String, dynamic>>.from(
                data['complementary'] as List? ?? [],
              );
              final missing = List<Map<String, dynamic>>.from(
                data['uncovered_conditions'] as List? ?? [],
              );
              final own = List<Map<String, dynamic>>.from(
                data['seeker_conditions'] as List? ?? [],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    data['mode'] == 'general'
                        ? 'General volunteer suggestions'
                        : data['mode'] == 'ai'
                        ? 'AI experience comparison active'
                        : 'Condition-based matching',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(data['notice'] as String? ?? ''),
                  const SizedBox(height: 10),
                  const Text(
                    'The percentage shows how many of your conditions are shared. It is not a medical assessment or a probability of successful support.',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (own.isEmpty && data['mode'] != 'general')
                    const EmptyState(
                      'Add your chronic conditions',
                      'Edit your profile to select at least one condition.',
                    ),
                  if (matches.isEmpty)
                    EmptyState(
                      data['mode'] == 'general'
                          ? 'No additional volunteers available'
                          : 'No additional matching volunteers',
                      data['mode'] == 'general'
                          ? 'Your pending requests and existing connections are excluded. Your conversations remain in Messages.'
                          : 'No other approved volunteers currently share an active condition with you. Pending requests and existing connections are excluded; your conversations remain in Messages.',
                    ),
                  if (team.isNotEmpty) ...[
                    const SectionTitle('Coverage suggestions'),
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'You can choose these volunteers separately:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          for (final member in team)
                            Builder(
                              builder: (context) {
                                final row = matches.firstWhere(
                                  (m) => m['user_id'] == member['user_id'],
                                );
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    row['full_name'] as String? ?? 'Volunteer',
                                  ),
                                  subtitle: Text(
                                    (member['covers'] as List)
                                        .map((c) => c['name'])
                                        .join(', '),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _open(row),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (missing.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No approved match currently covers: ${missing.map((c) => c['name']).join(', ')}.',
                      ),
                    ),
                  if (matches.isNotEmpty)
                    const SectionTitle('Ranked volunteers'),
                  for (final row in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SurfaceCard(
                        onTap: () => _open(row),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row['full_name'] as String? ?? 'Volunteer',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                                RoleChip(
                                  row['coverage_percent'] == null
                                      ? 'General suggestion'
                                      : '${row['coverage_percent']}% conditions',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (row['coverage_percent'] != null)
                              Text(
                                'Shared: ${(row['shared_conditions'] as List).map((c) => c['name']).join(', ')}',
                              ),
                            Text('Language: ${row['language']}'),
                            if (row['experience_similarity'] != null)
                              const Text(
                                'Experience description compared with AI',
                                style: TextStyle(fontSize: 12),
                              ),
                            const SizedBox(height: 8),
                            const Text(
                              'View profile and choose whether to request support →',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VolunteerDetailPage(
          volunteer: {
            ...row,
            'condition': (row['conditions'] as List? ?? [])
                .map((c) => c['name'])
                .join(', '),
          },
        ),
      ),
    );
    if (mounted) _reload();
  }
}
