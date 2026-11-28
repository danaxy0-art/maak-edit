import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../widgets/user_photo.dart';
import 'feedback.dart';
import 'ratings.dart' show VolunteerStatsLine;
import 'support.dart' show VolunteerDetailPage;
import 'ui.dart' show RoleChip, initials;

/// Another member's profile, opened by tapping a photo or name in a chat or
/// a Health Library comment. What is shown comes from get_maak_member_profile
/// (20261127010000_member_profiles.sql):
/// * volunteers: lived experience, conditions and language (as when browsing);
/// * help seekers: name and role only, unless the viewer has had a support
///   request with them. Their health details stay private otherwise.
class MemberProfilePage extends StatefulWidget {
  final String userId;

  /// Shown while loading, so the page never starts blank.
  final String? name;

  const MemberProfilePage({super.key, required this.userId, this.name});

  static Future<void> open(
    BuildContext context, {
    required String userId,
    String? name,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MemberProfilePage(userId: userId, name: name),
    ),
  );

  @override
  State<MemberProfilePage> createState() => _MemberProfilePageState();
}

class _MemberProfilePageState extends State<MemberProfilePage> {
  Map<String, dynamic>? _profile;
  String? _viewerRole;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SupabaseService.client.rpc(
        'get_maak_member_profile',
        params: {'p_user_id': widget.userId},
      );
      final viewerRole = await SupabaseService.getMyRole();
      if (!mounted) return;
      setState(() {
        _profile = Map<String, dynamic>.from(profile as Map);
        _viewerRole = viewerRole;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  bool get _isVolunteer => _profile?['role'] == 'volunteer';

  String get _name =>
      (_profile?['full_name'] ?? widget.name ?? 'Member').toString();

  @override
  Widget build(BuildContext context) => MaakPage(
    title: _isVolunteer ? 'Volunteer profile' : 'Member profile',
    onRefresh: _load,
    children: (context, wide) {
      if (_loading && _profile == null) {
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      }
      if (_profile == null) {
        return [
          StateMessage(
            title: 'Could not open this profile',
            message: _error == null
                ? 'This profile is not available.'
                : friendlyError(_error!),
            icon: Icons.person_off_outlined,
            retry: _load,
          ),
        ];
      }
      return [
        _identity(),
        const SizedBox(height: MaakSpace.lg),
        ..._details(),
      ];
    },
  );

  Widget _identity() {
    final p = _profile!;
    final since = DateTime.tryParse('${p['member_since'] ?? ''}')?.toLocal();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MaakSpace.xl,
        MaakSpace.xxl,
        MaakSpace.xl,
        MaakSpace.xl,
      ),
      decoration: BoxDecoration(
        gradient: MaakGradients.orb,
        borderRadius: BorderRadius.circular(MaakRadius.hero),
      ),
      child: Column(
        children: [
          UserPhoto(
            userId: widget.userId,
            size: 88,
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: MaakColors.surface,
                shape: BoxShape.circle,
              ),
              child: Text(
                initials(_name),
                style: MaakText.cardTitle.copyWith(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(height: MaakSpace.md),
          Text(
            _name,
            textAlign: TextAlign.center,
            style: MaakText.greeting.copyWith(fontSize: 28),
          ),
          const SizedBox(height: MaakSpace.sm),
          RoleChip(_isVolunteer ? 'Volunteer' : 'Help seeker'),
          if (_isVolunteer && p['approved'] == true)
            VolunteerStatsLine(
              volunteerId: widget.userId,
              center: true,
              explainBadge: true,
            ),
          if (since != null) ...[
            const SizedBox(height: MaakSpace.sm),
            Text(
              'Member since ${months[since.month - 1]} ${since.year}',
              style: MaakText.caption,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _details() {
    final p = _profile!;
    final description = (p['description'] ?? '').toString().trim();
    final conditions = conditionNames(p['condition']);
    final language = (p['language'] ?? '').toString();
    final hasSupportDetails = conditions.isNotEmpty || language.isNotEmpty;
    final self = p['is_self'] == true;
    // A help seeker looking at an approved volunteer can go on to request
    // support or a session from the full volunteer page.
    final canRequest = _viewerRole == 'help_seeker' &&
        _isVolunteer &&
        p['approved'] == true &&
        !self;
    return [
      if (self) ...[
        const StateMessage(
          message: 'This is how other members see your profile.',
          icon: Icons.visibility_outlined,
        ),
        const SizedBox(height: MaakSpace.md),
      ],
      if (_isVolunteer && description.isNotEmpty) ...[
        _Section(
          title: 'Lived experience',
          child: Text(
            description,
            style: MaakText.body.copyWith(
              color: MaakColors.onHero,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: MaakSpace.md),
      ],
      if (hasSupportDetails)
        _Section(
          title: _isVolunteer ? 'Support preferences' : 'Support details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (conditions.isNotEmpty) ...[
                const Text('Conditions', style: MaakText.caption),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final c in conditions) ConditionChip(c)],
                ),
              ],
              if (conditions.isNotEmpty && language.isNotEmpty)
                const SizedBox(height: MaakSpace.md),
              if (language.isNotEmpty) ...[
                const Text('Language', style: MaakText.caption),
                const SizedBox(height: 6),
                Text(language, style: MaakText.body.copyWith(color: MaakColors.ink)),
              ],
            ],
          ),
        )
      else if (!_isVolunteer)
        const StateMessage(
          message:
              'Health details are private. They are shared only with '
              'volunteers this member has asked for support.',
          icon: Icons.lock_outline,
        ),
      if (canRequest) ...[
        const SizedBox(height: MaakSpace.lg),
        PillButton(
          'Request support or a session',
          icon: Icons.volunteer_activism_outlined,
          expand: true,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VolunteerDetailPage(volunteer: p)),
          ),
        ),
      ],
    ];
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(MaakSpace.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: MaakText.section.copyWith(fontSize: 16)),
        ),
        const SizedBox(height: MaakSpace.md),
        child,
      ],
    ),
  );
}
