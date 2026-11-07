import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import 'feedback.dart';
import 'support.dart';
import 'ui.dart';
import 'ai_consent.dart';

class MatchingPage extends StatefulWidget {
  const MatchingPage({super.key});
  @override
  State<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends State<MatchingPage> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = _loadMatches();
  }

  Future<Map<String, dynamic>> _loadMatches() async {
    final enabled =
        await SupabaseService.client.rpc('has_maak_ai_consent') == true;
    if (!mounted) return {'activation_required': true};
    if (!enabled && !await requestAiMatchingActivation(context))
      return {'activation_required': true};
    try {
      return await SupabaseService.getMatches(useAi: true);
    } on AiMatchingDisabled {
      return {'activation_required': true};
    }
  }

  // Block body: an arrow would hand the new Future to setState, which Flutter
  // rejects in debug builds.
  void _reload() => setState(() {
    _future = _loadMatches();
  });

  @override
  Widget build(BuildContext context) => MaakPage(
    title: 'Your volunteer matches',
    actions: [
      IconButton(
        tooltip: 'Refresh matches',
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
      ),
    ],
    children: (context, wide) => wide
        ? [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 340, child: _intro()),
                const SizedBox(width: MaakSpace.xxl),
                Expanded(child: _results(wide)),
              ],
            ),
          ]
        : [_intro(), const SizedBox(height: MaakSpace.xxl), _results(wide)],
  );

  Widget _intro() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(
          'Support that understands you',
          style: MaakText.greeting.copyWith(fontSize: 26),
        ),
      ),
    ],
  );

  Widget _results(bool wide) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, s) {
      if (s.hasError) {
        return StateMessage(
          title: 'Could not load recommendations',
          message: friendlyError(s.error!),
          icon: Icons.cloud_off_outlined,
          retry: _reload,
        );
      }
      if (s.connectionState == ConnectionState.waiting || !s.hasData) {
        return const ListSkeleton(label: 'Loading matches', height: 128);
      }
      final data = s.data!;
      if (data['activation_required'] == true) {
        return SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.auto_awesome, color: MaakColors.ink, size: 30),
              const SizedBox(height: MaakSpace.sm),
              const Text('AI matching is off', style: MaakText.itemTitle),
              const SizedBox(height: MaakSpace.sm),
              const Text(
                'Activate AI matching to find suitable volunteers.',
                style: MaakText.body,
              ),
              const SizedBox(height: MaakSpace.lg),
              PillButton(
                'Activate AI matching',
                onPressed: _reload,
                expand: true,
              ),
            ],
          ),
        );
      }
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
      final cards = [
        for (final row in matches)
          _MatchCard(match: row, onTap: () => _open(row)),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (own.isEmpty && data['mode'] != 'general') ...[
            const StateMessage(
              title: 'Add your chronic conditions',
              message: 'Edit your profile to select at least one condition.',
              icon: Icons.edit_note,
            ),
          ],
          if (matches.isEmpty) ...[
            const SizedBox(height: MaakSpace.md),
            StateMessage(
              title: data['mode'] == 'general'
                  ? 'No additional volunteers available'
                  : 'No additional matching volunteers',
              message: data['mode'] == 'general'
                  ? 'Your pending requests and existing connections are excluded. Your conversations remain in Messages.'
                  : 'No other approved volunteers currently share an active condition with you. Pending requests and existing connections are excluded; your conversations remain in Messages.',
              icon: Icons.person_search_outlined,
            ),
          ],
          if (team.isNotEmpty) ...[
            const SectionHeader('Coverage suggestions'),
            _CoverageCard(team: team, matches: matches, onOpen: _open),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: MaakSpace.md),
            Text(
              'No approved match currently covers: ${missing.map((c) => c['name']).join(', ')}.',
              style: MaakText.body,
            ),
          ],
          if (matches.isNotEmpty) ...[
            // One column even on tablets: the results column beside the
            // controls is too narrow for two readable cards.
            const SectionHeader('Ranked volunteers'),
            for (final (i, card) in cards.indexed) ...[
              if (i > 0) const SizedBox(height: MaakSpace.md),
              card,
            ],
          ],
          const SizedBox(height: MaakSpace.lg),
          const Text(
            'The percentage shows how many of your conditions are shared. It is not a medical assessment or a probability of successful support.',
            style: MaakText.caption,
          ),
        ],
      );
    },
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

/// The AI opt-in. The whole card toggles the switch; the privacy text is
/// read together with the switch state by screen readers.
/// Volunteers who together cover the member's conditions.
class _CoverageCard extends StatelessWidget {
  final List<Map<String, dynamic>> team, matches;
  final void Function(Map<String, dynamic>) onOpen;
  const _CoverageCard({
    required this.team,
    required this.matches,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.symmetric(vertical: MaakSpace.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            MaakSpace.lg,
            MaakSpace.sm,
            MaakSpace.lg,
            MaakSpace.xs,
          ),
          child: Text(
            'You can choose these volunteers separately:',
            style: MaakText.caption,
          ),
        ),
        for (final (i, member) in team.indexed) ...[
          if (i > 0)
            const Divider(
              height: 1,
              indent: MaakSpace.lg,
              endIndent: MaakSpace.lg,
              color: MaakColors.border,
            ),
          Builder(
            builder: (context) {
              final row = matches.firstWhere(
                (m) => m['user_id'] == member['user_id'],
              );
              final name = row['full_name'] as String? ?? 'Volunteer';
              return InkWell(
                onTap: () => onOpen(row),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    MaakSpace.lg,
                    MaakSpace.md,
                    MaakSpace.sm,
                    MaakSpace.md,
                  ),
                  child: Row(
                    children: [
                      InitialsAvatar(
                        initials(name),
                        userId: row['user_id'] as String?,
                      ),
                      const SizedBox(width: MaakSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: MaakText.itemTitle),
                            Text(
                              (member['covers'] as List)
                                  .map((c) => c['name'])
                                  .join(', '),
                              style: MaakText.body.copyWith(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: MaakColors.muted),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}

class _MatchCard extends StatelessWidget {
  final Map<String, dynamic> match;
  final VoidCallback onTap;
  const _MatchCard({required this.match, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final name = match['full_name'] as String? ?? 'Volunteer';
    final coverage = match['coverage_percent'];
    return SoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                initials(name),
                userId: match['user_id'] as String?,
              ),
              const SizedBox(width: MaakSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: MaakText.itemTitle),
                    const SizedBox(height: 2),
                    MetaLine(
                      icon: Icons.language,
                      text: 'Language: ${match['language']}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MaakSpace.md),
          SoftChip(
            coverage == null ? 'General suggestion' : '$coverage% conditions',
            color: MaakColors.blush,
          ),
          if (coverage != null) ...[
            const SizedBox(height: MaakSpace.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Shared', style: MaakText.caption),
                for (final c in match['shared_conditions'] as List)
                  ConditionChip('${c['name']}', shared: true),
              ],
            ),
          ],
          if (match['experience_similarity'] != null) ...[
            const SizedBox(height: MaakSpace.sm),
            const Text(
              'Experience description compared with AI',
              style: MaakText.caption,
            ),
          ],
          const SizedBox(height: MaakSpace.md),
          const Divider(height: 1, color: MaakColors.border),
          const SizedBox(height: MaakSpace.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'View profile and choose whether to request support',
                  style: MaakText.itemTitle.copyWith(fontSize: 14),
                ),
              ),
              const Icon(Icons.chevron_right, color: MaakColors.muted),
            ],
          ),
        ],
      ),
    );
  }
}
