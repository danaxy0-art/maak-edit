import '../../lib/backend/validation/other_condition_policy.dart';

void main() {
  var count = 0;
  final cases = <String, bool>{
    'ab': false,
    'abc': true,
    'a' * 60: true,
    'a' * 61: false,
    '123': false,
    '١٢٣': false,
    'https://abc.com': false,
    'www.abc.com': false,
    'hello@example.com': false,
    'Type 2 diabetes': true,
    'حالة صحية': true,
    '   ': false,
    "Crohn's disease": true,
  };
  for (final entry in cases.entries) {
    if ((validateOtherCondition(entry.key) == null) != entry.value)
      throw StateError('Unexpected validation: ${entry.key}');
    count++;
  }
  final options = [
    <String, dynamic>{
      'name': 'Diabetes',
      'is_active': true,
      'aliases': ['سكر', 'سكري'],
    },
    <String, dynamic>{'name': 'Other', 'is_other': true, 'is_active': true},
    <String, dynamic>{'name': 'Inactive diabetes', 'is_active': false},
  ];
  if (suggestConditions('سكر', options).single['name'] != 'Diabetes')
    throw StateError('Arabic alias did not suggest canonical condition');
  count++;
  if (suggestConditions('diab', options).length != 1)
    throw StateError('Inactive condition suggested');
  count++;
  if (suggestConditions('', options).isNotEmpty)
    throw StateError('Empty query should not suggest');
  count++;
  if (suggestConditions('Other', options).isNotEmpty)
    throw StateError('Other is not a canonical suggestion');
  count++;
  print('$count Other validation and suggestion checks passed');
}
