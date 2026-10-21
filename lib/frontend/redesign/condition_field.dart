import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'feedback.dart';
import 'ui.dart';
import 'app_text_field.dart';

class ConditionField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  const ConditionField({
    super.key,
    this.value,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  State<ConditionField> createState() => _ConditionFieldState();
}

class _ConditionFieldState extends State<ConditionField> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = SupabaseService.getConditions();
  }

  void _retry() => setState(() => _future = SupabaseService.getConditions());
  Future<void> _select(List<String> names, FormFieldState<String> field) async {
    var query = '';
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .68,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Select your chronic condition',
                    style: TextStyle(
                      fontFamily: 'MaakSerif',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    onChanged: (v) => update(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search conditions...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final name in names.where(
                          (n) => n.toLowerCase().contains(query.toLowerCase()),
                        ))
                          ListTile(
                            title: Text(name),
                            trailing: widget.value == name
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.primaryNavy,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, name),
                          ),
                        if (!names.any(
                          (n) => n.toLowerCase().contains(query.toLowerCase()),
                        ))
                          const EmptyState(
                            'No matching conditions',
                            'Try another search term.',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      field.didChange(value);
      widget.onChanged(value);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return FormField<String>(
          validator: (_) =>
              'Chronic conditions could not be loaded. Reload before submitting.',
          builder: (_) => SurfaceCard(
            child: Column(
              children: [
                FieldErrorNotice(
                  'Unable to load chronic conditions. ${friendlyError(snapshot.error!)}',
                ),
                TextButton(
                  onPressed: _retry,
                  child: const Text('Reload conditions'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return FormField<String>(
          validator: (_) => 'Please wait for chronic conditions to load.',
          builder: (_) => const LinearProgressIndicator(),
        );
      }
      final names = snapshot.data!.map((r) => r['name'] as String).toList();
      if (names.isEmpty) {
        return FormField<String>(
          validator: (_) => 'No active chronic conditions are available.',
          builder: (_) => SurfaceCard(
            child: Column(
              children: [
                const FieldErrorNotice(
                  'No active chronic conditions are available. Please contact the administrator.',
                ),
                TextButton(
                  onPressed: _retry,
                  child: const Text('Reload conditions'),
                ),
              ],
            ),
          ),
        );
      }
      return FormField<String>(
        key: ValueKey(widget.value),
        initialValue: widget.value,
        autovalidateMode: AutovalidateMode.disabled,
        validator: (v) =>
            v == null || v.isEmpty ? 'Select your chronic condition' : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.enabled ? () => _select(names, field) : null,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  enabledBorder: field.hasError
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.error),
                        )
                      : null,
                  prefixIcon: const Icon(Icons.favorite_border),
                  suffixIcon: const Icon(Icons.expand_more),
                  enabled: widget.enabled,
                ),
                child: Text(
                  widget.value ?? 'Select your condition',
                  style: TextStyle(
                    color: widget.value == null
                        ? AppColors.textMuted
                        : AppColors.textDark,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            // Error message sits below the selector.
            if (field.hasError) FieldErrorNotice(field.errorText!),
          ],
        ),
      );
    },
  );
}
