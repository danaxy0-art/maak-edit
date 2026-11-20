String normalizeOtherCondition(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');
String? validateOtherCondition(String? value) {
  final text = normalizeOtherCondition(value ?? '');
  if (text.runes.length < 3 || text.runes.length > 60)
    return 'Enter 3–60 characters.';
  if (!RegExp(r'[A-Za-zء-ي]').hasMatch(text))
    return 'Enter a condition name, not numbers only.';
  if (RegExp(r'https?://|www\.|@', caseSensitive: false).hasMatch(text) ||
      !RegExp(r"^[A-Za-zء-يً-ْ٠-٩0-9 ()'’/-]+$").hasMatch(text))
    return 'Use a condition name without links or unsupported symbols.';
  return null;
}

List<Map<String, dynamic>> suggestConditions(
  String query,
  List<Map<String, dynamic>> options,
) {
  final q = normalizeOtherCondition(query).toLowerCase();
  if (q.isEmpty) return [];
  return options
      .where(
        (c) =>
            c['is_other'] != true &&
            c['name'] != 'Other' &&
            c['is_active'] == true &&
            ([
              c['name'],
              ...List<String>.from(c['aliases'] as List? ?? []),
            ].any((name) => name.toString().toLowerCase().contains(q))),
      )
      .take(6)
      .toList();
}
