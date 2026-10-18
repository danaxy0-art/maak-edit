import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import 'app_text_field.dart';
import 'feedback.dart';
import 'ui.dart';

class MultiConditionField extends StatefulWidget {
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  const MultiConditionField({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  State<MultiConditionField> createState() => _MultiConditionFieldState();
}

class _MultiConditionFieldState extends State<MultiConditionField> {
  late Future<List<Map<String, dynamic>>> _future;
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
                          (n) => n.toLowerCase().contains(query),
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
          ],
        ),
      );
    },
  );
}
