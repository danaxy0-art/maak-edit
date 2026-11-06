// ADDED: report a message (reason + optional description). New file.
import 'package:flutter/material.dart';

import '../../backend/services/supabase_service.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../theme/app_theme.dart';
import 'feedback.dart';
import 'validated_text_area.dart';

/// Reasons shown to the user, in order, with the value stored in `reports.reason`.
const kReportReasons = <(String, String)>[
  ('inappropriate_language', 'Inappropriate language'),
  ('unwanted_medical_advice', 'Unwanted medical advice'),
  ('harassment', 'Harassment'),
  ('spam', 'Spam'),
  ('other', 'Other'),
];

const kReportDescriptionMax = 500;

/// Opens the report dialog. Shows a success message when the report was sent.
Future<void> showReportMessageDialog(
  BuildContext context, {
  required String messageId,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => ReportMessageDialog(messageId: messageId),
  );
  if (sent == true && context.mounted) {
    showSuccess(context, 'Report sent. An admin will review it.');
  }
}

class ReportMessageDialog extends StatefulWidget {
  final String messageId;

  /// Test hook: replaces the Supabase call.
  final Future<void> Function(String reason, String? description)? submit;
  const ReportMessageDialog({super.key, required this.messageId, this.submit});
  @override
  State<ReportMessageDialog> createState() => _ReportMessageDialogState();
}

class _ReportMessageDialogState extends State<ReportMessageDialog> {
  final _description = TextEditingController();
  String? _reason;
  bool _showReasonError = false, _busy = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

 Future<void> _send() async {
  if (_busy) return;

  if (_reason == null) {
    setState(() => _showReasonError = true);
    return;
  }

  // Validate optional description length
  final text = _description.text.trim();

  if (text.length > kReportDescriptionMax) {
         showAppError(
        context,
        ArgumentError('Description must be 500 characters or fewer.'),
      );
    return;
  }

  setState(() => _busy = true);

  try {
      final submit = widget.submit;
      if (submit != null) {
        await submit(_reason!, text.isEmpty ? null : text);
      } else {
        await SupabaseService.reportMessage(
          messageId: widget.messageId,
          reason: _reason!,
          description: text.isEmpty ? null : text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showAppError(context, e, retry: _send);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: MaakColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    title: const Text('Report this message', style: MaakText.cardTitle),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why are you reporting it?', style: MaakText.body),
          const SizedBox(height: 8),
          for (final r in kReportReasons)
            ListTile(
              key: ValueKey('reason_${r.$1}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              enabled: !_busy,
              leading: Icon(
                _reason == r.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _reason == r.$1
                    ? AppColors.primaryNavy
                    : AppColors.textMuted,
              ),
              title: Text(r.$2),
              onTap: () => setState(() {
                _reason = r.$1;
                _showReasonError = false;
              }),
            ),
          if (_showReasonError)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Choose a reason to continue.',
                key: ValueKey('reason_error'),
                style: TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          ValidatedTextArea(
            controller: _description,
            validator: (_) => null,
            maxLength: kReportDescriptionMax,
            enabled: !_busy,
            maxLines: 4,
            minLines: 3,
            hintText: 'Add details (optional)',
          ),
        ],
      ),
    ),
    actionsPadding: const EdgeInsets.fromLTRB(
      MaakSpace.xl,
      0,
      MaakSpace.xl,
      MaakSpace.xl,
    ),
    actions: [
      PillButton(
        'Cancel',
        outlined: true,
        compact: true,
        onPressed: _busy ? null : () => Navigator.pop(context, false),
      ),
      PillButton(
        _busy ? 'Sending...' : 'Send report',
        compact: true,
        onPressed: _busy ? null : _send,
      ),
    ],
  );
}
