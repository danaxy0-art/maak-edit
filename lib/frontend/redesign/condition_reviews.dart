import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../../backend/validation/other_condition_policy.dart';
import 'app_text_field.dart';
import 'feedback.dart';
import 'support.dart';
import 'ui.dart';

class ConditionRequestsPage extends StatefulWidget {
  const ConditionRequestsPage({super.key});
  @override
  State<ConditionRequestsPage> createState() => _ConditionRequestsPageState();
}

class _ConditionRequestsPageState extends State<ConditionRequestsPage> {
  final Set<String> _checking = {};
  Future<void> _review(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback refresh,
  ) async {
    try {
      final options = await SupabaseService.getConditions();
      if (!context.mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _ReviewConditionDialog(
          request: row,
          options: options.where((c) => c['is_other'] != true).toList(),
        ),
      );
      if (saved == true && context.mounted) {
        showSuccess(context, 'Condition decision saved.');
        refresh();
      }
    } catch (e) {
      if (context.mounted) showAppError(context, e);
    }
  }

  Future<void> _check(
    BuildContext context,
    String id,
    VoidCallback refresh,
  ) async {
    if (_checking.contains(id)) return;
    setState(() => _checking.add(id));
    try {
      final message = await SupabaseService.checkConditionName(id);
      if (!context.mounted) return;
      showSuccess(context, message);
      refresh();
    } catch (e) {
      if (context.mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _checking.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => DataListPage(
    title: 'Condition review requests',
    load: SupabaseService.getConditionRequests,
    emptyTitle: 'No condition requests',
    emptyText: 'New Other condition names will appear here.',
    header: const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Text(
        'AI flags are advisory. Accept, link or reject each request yourself.',
      ),
    ),
    item: (context, row, refresh) => SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row['submitted_name'] as String,
            style: const TextStyle(fontFamily: 'MaakSerif', fontSize: 23),
          ),
          Text('Submitted by: ${row['full_name']}'),
          Text('Status: ${row['status']}'),
          if (row['ai_state'] == 'warning')
            const FieldErrorNotice(
              'AI warning: this may not be a health condition. Review manually.',
            ),
          if (row['ai_state'] == 'health')
            const Text(
              'AI: name appears health-related. Admin decision still required.',
            ),
          if (row['ai_state'] == 'unknown')
            const Text(
              'AI check unavailable or uncertain; manual review is available.',
            ),
          if (row['reason'] != null) Text('Reason: ${row['reason']}'),
          if (row['status'] == 'pending')
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _checking.contains(row['id'])
                      ? null
                      : () => _review(context, row, refresh),
                  child: const Text('Accept / Link / Reject'),
                ),
                OutlinedButton.icon(
                  onPressed: _checking.contains(row['id'])
                      ? null
                      : () => _check(context, row['id'] as String, refresh),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    _checking.contains(row['id'])
                        ? 'Checking...'
                        : 'Optional AI check',
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _ReviewConditionDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final List<Map<String, dynamic>> options;
  const _ReviewConditionDialog({required this.request, required this.options});
  @override
  State<_ReviewConditionDialog> createState() => _ReviewConditionDialogState();
}

class _ReviewConditionDialogState extends State<_ReviewConditionDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _reason = TextEditingController();
  String _action = 'accept';
  String? _target;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.request['submitted_name'] as String,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.reviewConditionRequest(
        widget.request['id'] as String,
        _action,
        conditionId: _target,
        name: _name.text,
        reason: _reason.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Review condition request'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Submitted name: ${widget.request['submitted_name']}'),
              DropdownButtonFormField<String>(
                initialValue: _action,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'accept',
                    child: Text('Accept as a new condition'),
                  ),
                  DropdownMenuItem(
                    value: 'link',
                    child: Text('Link to an existing condition'),
                  ),
                  DropdownMenuItem(value: 'reject', child: Text('Reject')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _action = v!),
              ),
              if (_action == 'accept') ...[
                const FieldLabel(
                  'Canonical condition name',
                  requiredField: true,
                ),
                AppTextField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 60,
                  validator: validateOtherCondition,
                ),
              ],
              if (_action == 'link')
                DropdownButtonFormField<String>(
                  initialValue: _target,
                  isExpanded: true,
                  hint: const Text('Choose existing condition'),
                  items: widget.options
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(c['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: _busy ? null : (v) => setState(() => _target = v),
                  validator: (v) => v == null ? 'Select a condition' : null,
                ),
              if (_action == 'reject') ...[
                const FieldLabel('Rejection reason', requiredField: true),
                AppTextField(
                  controller: _reason,
                  enabled: !_busy,
                  maxLength: 500,
                  maxLines: 3,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a rejection reason'
                      : null,
                ),
              ],
              if (_error != null) FieldErrorNotice(_error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving...' : 'Save decision'),
        ),
      ],
    ),
  );
}
