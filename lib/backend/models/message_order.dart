/// Stable chronological order for both the initial query and realtime updates.
List<Map<String, dynamic>> chronologicalMessages(
  List<Map<String, dynamic>> rows,
) => List<Map<String, dynamic>>.from(rows)
  ..sort((a, b) {
    final order = DateTime.parse(a['created_at'] as String)
        .compareTo(DateTime.parse(b['created_at'] as String));
    return order != 0
        ? order
        : (a['id'] as String).compareTo(b['id'] as String);
  });
