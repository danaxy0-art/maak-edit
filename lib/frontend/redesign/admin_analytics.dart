
part of 'admin.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() =>
      _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState
    extends State<AdminAnalyticsPage> {

  int? _days;

  late Future<Map<String, dynamic>> _future;

  static const _accent = Color(0xFFB87580);
  static const _softPink = Color(0xFFFFF1F3);

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() {
    return SupabaseService.getAdminAnalytics(
      days: _days,
    );
  }

  Future<void> _refresh() async {
    final future = _fetch();

    setState(() {
      _future = future;
    });

    try {
      await future;
    } catch (_) {
      // FutureBuilder displays the error.
    }
  }

  void _changeFilter(int? days) {
    if (_days == days) return;

    setState(() {
      _days = days;
      _future = _fetch();
    });
  }

  Map<String, dynamic> _section(
      Map<String, dynamic> data,
      String key,
      ) {
    return Map<String, dynamic>.from(
      data[key] as Map? ?? {},
    );
  }

  int _number(Map<String, dynamic> data, String key) {
    return (data[key] as num?)?.toInt() ?? 0;
  }

  String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return '${minutes}m ${remaining}s';
    }

    return '${remaining}s';
  }

  @override
  Widget build(BuildContext context) {
    return BotanicalScaffold(
      body: SafeArea(
        child: _AdminResponsiveBody(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics:
              const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                LogoHeader(
                  trailing: IconButton(
                    tooltip: 'Refresh analytics',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Platform analytics',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Monitor platform activity and performance.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 18),

                _timeFilter(),

                const SizedBox(height: 20),

                FutureBuilder<Map<String, dynamic>>(
                  future: _future,
                  builder: (context, snapshot) {

                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return EmptyState(
                        'Could not load analytics',
                        friendlyError(snapshot.error!),
                        retry: () {
                          _refresh();
                        },
                      );
                    }

                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    return _dashboard(snapshot.data!);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeFilter() {
    return Row(
      children: [
        _filterChip('7 days', 7),
        const SizedBox(width: 8),
        _filterChip('30 days', 30),
        const SizedBox(width: 8),
        _filterChip('All time', null),
      ],
    );
  }

  Widget _filterChip(String label, int? days) {
    final selected = _days == days;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _changeFilter(days),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _accent
                  : const Color(0xFFEAD8DC),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard(Map<String, dynamic> data) {
    final users = _section(data, 'users');
    final applications = _section(data, 'applications');
    final connections = _section(data, 'connections');
    final sessions = _section(data, 'sessions');
    final calls = _section(data, 'calls');
    final safety = _section(data, 'safety');
    final ratings = _section(data, 'ratings');

    final growth = (data['growth'] as List? ?? [])
        .map((item) =>
    Map<String, dynamic>.from(item as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        // USERS
        _heading('Users', 'Current accounts'),

        _panel([
          Row(
            children: [
              _metricIcon(Icons.people_outline),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Registered users',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              _value(_number(users, 'registered').toString()),
            ],
          ),

          const SizedBox(height: 18),

          _distributionBar(
            _number(users, 'volunteers'),
            _number(users, 'help_seekers'),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _legend(
                  'Volunteers',
                  _number(users, 'volunteers'),
                  _accent,
                ),
              ),
              Expanded(
                child: _legend(
                  'Help Seekers',
                  _number(users, 'help_seekers'),
                  const Color(0xFFE6C5CB),
                ),
              ),
            ],
          ),

          const Divider(height: 30),

          _metricRow(
            'Active accounts',
            _number(users, 'active').toString(),
            Icons.person_outline,
            'Deactivated',
            _number(users, 'deactivated').toString(),
            Icons.person_off_outlined,
          ),

          const SizedBox(height: 8),

          _metricRow(
            'Active volunteers',
            _number(users, 'active_volunteers').toString(),
            Icons.volunteer_activism_outlined,
            'Active help seekers',
            _number(users, 'active_help_seekers').toString(),
            Icons.favorite_border,
          ),
        ]),

        // GROWTH
        _heading('User growth', 'Selected period'),

        _panel([
          const Text(
            'New registrations',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
          ),

          _value(
            _number(users, 'new_registrations').toString(),
          ),

          const SizedBox(height: 18),

          _growthChart(growth),
        ]),

        // CONNECTIONS
        _heading('Connections', 'Current request statuses'),

        _panel([
          _summary(
            'Total support requests',
            _number(connections, 'total'),
            Icons.handshake_outlined,
          ),

          const Divider(height: 26),

          _metricRow(
            'Active',
            _number(connections, 'active').toString(),
            Icons.link,
            'Pending',
            _number(connections, 'pending').toString(),
            Icons.schedule,
          ),

          const SizedBox(height: 8),

          _metricRow(
            'Ended',
            _number(connections, 'ended').toString(),
            Icons.link_off,
            'Restricted',
            _number(connections, 'restricted').toString(),
            Icons.lock_outline,
          ),

          const SizedBox(height: 8),

          _detailRow(
            'Declined',
            _number(connections, 'declined'),
          ),

          _detailRow(
            'Canceled',
            _number(connections, 'canceled'),
          ),
        ]),

        // SESSIONS
        _heading('Support sessions', 'Selected period'),

        _panel([
          _summary(
            'Total bookings',
            _number(sessions, 'total'),
            Icons.calendar_month_outlined,
          ),

          const Divider(height: 26),

          _metricRow(
            'Confirmed',
            _number(sessions, 'confirmed').toString(),
            Icons.event_available,
            'Pending',
            _number(sessions, 'pending').toString(),
            Icons.schedule,
          ),

          const SizedBox(height: 8),

          _detailRow(
            'Rejected',
            _number(sessions, 'rejected'),
          ),

          _detailRow(
            'Canceled',
            _number(sessions, 'canceled'),
          ),
        ]),

        // CALLS
        _heading('Voice calls', 'Selected period'),

        _panel([
          _summary(
            'Total voice calls',
            _number(calls, 'total'),
            Icons.call_outlined,
          ),

          const Divider(height: 26),

          _metricRow(
            'Connected',
            _number(calls, 'connected').toString(),
            Icons.phone_in_talk_outlined,
            'Missed',
            _number(calls, 'missed').toString(),
            Icons.call_missed,
          ),

          const SizedBox(height: 8),

          _metricRow(
            'Total duration',
            _duration(
              _number(calls, 'total_duration_seconds'),
            ),
            Icons.timer_outlined,
            'Average duration',
            _duration(
              _number(calls, 'average_duration_seconds'),
            ),
            Icons.av_timer,
          ),
        ]),

        // APPLICATIONS
        _heading(
          'Volunteer applications',
          'Current statuses',
        ),

        _panel([
          _summary(
            'Total applications',
            _number(applications, 'total'),
            Icons.assignment_outlined,
          ),

          const Divider(height: 26),

          _detailRow(
            'Approved',
            _number(applications, 'approved'),
          ),

          _detailRow(
            'Pending review',
            _number(applications, 'pending'),
          ),

          _detailRow(
            'Rejected',
            _number(applications, 'rejected'),
          ),
        ]),

        // SAFETY
        _heading('Safety & moderation', 'Platform safety'),

        _panel([
          const Text(
            'Current moderation status',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 10),

          _metricRow(
            'Open reports',
            _number(safety, 'open_reports').toString(),
            Icons.flag_outlined,
            'Blocked accounts',
            _number(safety, 'blocked_accounts').toString(),
            Icons.block,
          ),

          const SizedBox(height: 8),

          _detailRow(
            'Pending appeals',
            _number(safety, 'pending_appeals'),
          ),

          const Divider(height: 26),

          const Text(
            'Activity in selected period',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          _detailRow(
            'Total reports',
            _number(safety, 'total_reports'),
          ),

          _detailRow(
            'Reviewed reports',
            _number(safety, 'reviewed_reports'),
          ),

          _detailRow(
            'Dismissed reports',
            _number(safety, 'dismissed_reports'),
          ),

          _detailRow(
            'Conversation ended',
            _number(safety, 'conversation_ended_reports'),
          ),

          _detailRow(
            'Total appeals',
            _number(safety, 'total_appeals'),
          ),
        ]),

        // RATINGS
        _heading('Volunteer ratings', 'Selected period'),

        _panel([
          Row(
            children: [
              _metricIcon(Icons.star_outline),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      ratings['average'] == null
                          ? 'No ratings yet'
                          : '${(ratings['average'] as num).toStringAsFixed(1)} / 5',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'DMSans',
                      ),
                    ),

                    Text(
                      'Based on ${_number(ratings, 'total')} ratings',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (ratings['average'] != null) ...[
            const SizedBox(height: 14),

            Row(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final average =
                (ratings['average'] as num).toDouble();

                final remaining = average - index;

                return Icon(
                  remaining >= 1
                      ? Icons.star
                      : remaining >= 0.5
                      ? Icons.star_half
                      : Icons.star_border,
                  color: const Color(0xFFD4A64D),
                  size: 28,
                );
              }),
            ),
          ],
        ]),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _heading(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 18,
        bottom: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFEAD8DC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _value(String value) {
    return Text(
      value,
      style: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 30,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _metricIcon(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: _softPink,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: _accent,
        size: 23,
      ),
    );
  }

  Widget _summary(
      String label,
      int value,
      IconData icon,
      ) {
    return Row(
      children: [
        _metricIcon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _value(value.toString()),
      ],
    );
  }

  Widget _metricRow(
      String firstLabel,
      String firstValue,
      IconData firstIcon,
      String secondLabel,
      String secondValue,
      IconData secondIcon,
      ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _metric(
              firstLabel,
              firstValue,
              firstIcon,
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: _metric(
              secondLabel,
              secondValue,
              secondIcon,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
      String label,
      String value,
      IconData icon,
      ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _softPink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _accent, size: 20),

              const SizedBox(width: 8),

              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'DMSans',
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ),

          Text(
            value.toString(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _distributionBar(int first, int second) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 12,
        child: first + second == 0
            ? Container(color: _softPink)
            : Row(
          children: [
            if (first > 0)
              Expanded(
                flex: first,
                child: Container(color: _accent),
              ),

            if (second > 0)
              Expanded(
                flex: second,
                child: Container(
                  color: const Color(0xFFE6C5CB),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legend(
      String label,
      int value,
      Color color,
      ) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 6),

        Expanded(
          child: Text(
            '$label ($value)',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _growthChart(
      List<Map<String, dynamic>> growth,
      ) {
    if (growth.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No registrations in this period.',
            style: TextStyle(
              color: AppColors.textMuted,
            ),
          ),
        ),
      );
    }

    int maximum = 1;

    for (final item in growth) {
      final count = _number(item, 'count');
      if (count > maximum) maximum = count;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: growth.map((item) {
              final count = _number(item, 'count');
              final date = item['date'].toString();

              return SizedBox(
                width: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      count.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Container(
                      width: 25,
                      height: 100 * count / maximum,
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius:
                        const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),

                    const SizedBox(height: 7),

                    Text(
                      date.length >= 10
                          ? date.substring(5)
                          : date,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 10),

        const Text(
          'Dates with new registrations',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
