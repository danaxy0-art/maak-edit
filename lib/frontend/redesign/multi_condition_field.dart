import 'package:flutter/material.dart';

import '../../backend/validation/other_condition_policy.dart';

import '../../backend/services/supabase_service.dart';
import 'app_text_field.dart';
import 'feedback.dart';
import 'ui.dart';

class MultiConditionField extends StatefulWidget {
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  final TextEditingController? otherController;
  const MultiConditionField({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
    this.otherController,
  });
  @override
  State<MultiConditionField> createState() => _MultiConditionFieldState();
}

class _MultiConditionFieldState extends State<MultiConditionField> {
  late Future<List<Map<String, dynamic>>> _future;
  Map<String, List<String>> _optionAliases = {};
  final _fallback = TextEditingController();
  TextEditingController get _other => widget.otherController ?? _fallback;
  @override
  void dispose() {
    _fallback.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _future = SupabaseService.getConditions();
  }

  Future<void> _select(
    List<String> names,
    FormFieldState<List<String>> field,
  ) async {
    final selected = widget.values.toSet();
    var query = '';
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Select your conditions',
                    style: TextStyle(fontFamily: 'MaakSerif', fontSize: 24),
                  ),
                  const Text('Choose all that apply (up to 20).'),
                  TextField(
                    maxLength: 100,
                    onChanged: (v) => update(() => query = v.toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Search conditions...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final name in names.where(
                          (n) =>
                              n.toLowerCase().contains(query) ||
                              (_optionAliases[n] ?? []).any(
                                (alias) => alias.toLowerCase().contains(query),
                              ),
                        ))
                          CheckboxListTile(
                            title: Text(name),
                            value: selected.contains(name),
                            onChanged: (v) => update(() {
                              if (v == true && selected.length < 20) {
                                selected.add(name);
                              } else if (v == false) {
                                selected.remove(name);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  PrimaryButton(
                    'Save selection',
                    onPressed: () => Navigator.pop(context, selected.toList()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      field.didChange(result);
      widget.onChanged(result);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.hasError) {
        return FormField<List<String>>(
          validator: (_) => 'Load conditions before continuing.',
          builder: (_) => snapshot.hasError
              ? Column(
                  children: [
                    FieldErrorNotice(friendlyError(snapshot.error!)),
                    TextButton(
                      onPressed: () => setState(
                        () => _future = SupabaseService.getConditions(),
                      ),
                      child: const Text('Reload conditions'),
                    ),
                  ],
                )
              : const LinearProgressIndicator(),
        );
      }
      _optionAliases = {
        for (final row in snapshot.data!)
          row['name'] as String: List<String>.from(
            row['aliases'] as List? ?? [],
          ),
      };
      final active = snapshot.data!.map((r) => r['name'] as String).toList();
      // Existing disabled choices can be retained but cannot be newly added.
      final names = {...active, ...widget.values}.toList();
      return FormField<List<String>>(
        key: ValueKey(widget.values.join('|')),
        initialValue: widget.values,
        validator: (_) => widget.values.isEmpty
            ? 'Select at least one chronic condition'
            : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (field.hasError) FieldErrorNotice(field.errorText!),
            if (names.isEmpty)
              const FieldErrorNotice(
                'No active conditions. Please contact the administrator.',
              ),
            OutlinedButton.icon(
              onPressed: widget.enabled && names.isNotEmpty
                  ? () => _select(names, field)
                  : null,
              icon: const Icon(Icons.favorite_border),
              label: Text(
                widget.values.isEmpty
                    ? 'Select your conditions'
                    : widget.values.join(', '),
              ),
            ),
            if (widget.values.contains('Other')) ...[
              const FieldLabel('Other condition name', requiredField: true),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _other,
                builder: (context, value, child) {
                  final suggestions = suggestConditions(
                    value.text,
                    snapshot.data!,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextField(
                        controller: _other,
                        enabled: widget.enabled,
                        maxLength: 60,
                        validator: (v) {
                          final error = validateOtherCondition(v);
                          if (error != null) return error;
                          final q = normalizeOtherCondition(v ?? '')
                              .toLowerCase();
                          if (snapshot.data!.any(
                            (c) =>
                                c['is_other'] != true &&
                                c['name'] != 'Other' &&
                                ([
                                  c['name'],
                                  ...List<String>.from(
                                    c['aliases'] as List? ?? [],
                                  ),
                                ].any(
                                  (n) => n.toString().trim().toLowerCase() == q,
                                )),
                          ))
                            return 'This condition is already listed. Select it from the suggestions.';
                          return null;
                        },
                        decoration: const InputDecoration(
                          hintText: 'Type a condition name',
                        ),
                      ),
                      for (final option in suggestions)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.search),
                          title: Text(option['name'] as String),
                          subtitle: const Text(
                            'Choose this existing condition',
                          ),
                          onTap: !widget.enabled
                              ? null
                              : () {
                                  final selected = widget.values.toSet()
                                    ..remove('Other')
                                    ..add(option['name'] as String);
                                  _other.clear();
                                  field.didChange(selected.toList());
                                  widget.onChanged(selected.toList());
                                },
                        ),
                    ],
                  );
                },
              ),
              const Text(
                'Pending admin review. Your account remains available. This text is not used for matching. An optional admin AI check may examine the name only.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      );
    },
  );
}
