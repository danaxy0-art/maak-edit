import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../backend/services/supabase_service.dart';
import '../../backend/validation/form_policy.dart';
import '../redesign/app_text_field.dart';
import '../redesign/feedback.dart';
import '../redesign/ui.dart';
import '../redesign/profile.dart';
import '../redesign/validated_text_area.dart';
import '../theme/app_theme.dart';
import 'auth_gate.dart';

/// Shown instead of the app while an administrator has restricted the account.
/// The database already denies every protected action; this screen explains
/// why and offers what is left: appealing, checking again and signing out.
class BlockedAccountScreen extends StatefulWidget {
  final String reason;
  final String? blockedAt;
  const BlockedAccountScreen({super.key, required this.reason, this.blockedAt});

  @override
  State<BlockedAccountScreen> createState() => _BlockedAccountScreenState();
}

class _BlockedAccountScreenState extends State<BlockedAccountScreen> {
  // Appeal state for the current restriction; null until loaded, and stays
  // null with _appealsAvailable false when the appeals migration is missing.
  Map<String, dynamic>? _appeal;
  Object? _appealError;
  bool _loadingAppeal = true;
  bool _appealsAvailable = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadAppeal();
  }

  Future<void> _loadAppeal() async {
    setState(() {
      _loadingAppeal = true;
      _appealError = null;
    });
    try {
      final status = await SupabaseService.getMyAppealStatus().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _appeal = status;
        _appealsAvailable = status != null;
      });
    } catch (error) {
      debugPrint('Appeal status load failed: ${error.runtimeType}');
      if (mounted) setState(() => _appealError = error);
    } finally {
      if (mounted) setState(() => _loadingAppeal = false);
    }
  }

  Future<void> _requestAppeal() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await showDialog<Object>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AppealDialog(),
      );
      if (!mounted || result == null) return;
      if (result is Map<String, dynamic>) {
        setState(() => _appeal = result);
        showSuccess(context, 'Appeal submitted.');
      } else {
        // The state changed elsewhere (already pending, limit, reactivated).
        await _loadAppeal();
        if (mounted) showAppError(context, result);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = formatDay(widget.blockedAt);
    return AuthCanvas(
      heroTitle: 'Account status',
      heroSubtitle: "Your Ma'ak account",
      // A shorter hero keeps the reason and actions close to the top on phones.
      heroHeight: 270,
      back: false,
      children: [
        const Text(
          'Your account has been restricted',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'MaakSerif',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'An administrator has restricted this account. Support, messages and sessions are unavailable until it is reactivated.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reason',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                widget.reason.trim().isEmpty
                    ? 'No reason was recorded. Please contact the administrator.'
                    : widget.reason,
                style: const TextStyle(color: AppColors.textMuted, height: 1.6),
              ),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Restricted on',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(date, style: const TextStyle(color: AppColors.textMuted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Kept directly under the reason so both stay on screen on phones;
        // the appeal section follows. Wraps onto two lines with large text.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            // Re-runs the normal routing, so a reactivated account continues.
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (_) => false,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
            TextButton(
              onPressed: () => logout(context),
              child: const Text('Log out'),
            ),
          ],
        ),
        if (_appealsAvailable) ...[
          const SizedBox(height: 16),
          _appealSection(),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _appealSection() {
    if (_loadingAppeal && _appeal == null) {
      return const SurfaceCard(
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading appeal details...')),
          ],
        ),
      );
    }
    if (_appealError != null && _appeal == null) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Appeal details could not be loaded. ${friendlyError(_appealError!)}',
              style: const TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loadAppeal,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      );
    }
    final status = _appeal!;
    if (status['blocked'] != true) {
      return const _AppealCard(
        title: 'Appeal',
        children: [
          Text(
            'This account is no longer restricted. Tap Check again to continue.',
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
        ],
      );
    }
    final appeals = List<Map<String, dynamic>>.from(
      status['appeals'] as List? ?? const [],
    );
    final latest = appeals.isEmpty ? null : appeals.first;
    final remaining = status['appeals_remaining'] as int? ?? 0;
    final max = status['max_appeals'] as int? ?? 3;
    final canAppeal = status['can_appeal'] == true;
    final unavailable = switch (status['unavailable_reason']) {
      'appeal_pending' =>
        "Your appeal is being reviewed. You can't submit another until an administrator responds.",
      'appeal_limit_reached' =>
        'You have used all $max appeals for this restriction.',
      _ => null,
    };
    return _AppealCard(
      title: 'Appeal',
      children: [
        if (latest != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Appeal ${latest['attempt']} of $max',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _AppealStatusChip(latest['status'] as String?),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Submitted ${formatDay(latest['submitted_at'] as String?)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if ((latest['decision_note'] as String? ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              "Administrator's response",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              latest['decision_note'] as String,
              style: const TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
          ],
          const SizedBox(height: 14),
        ] else
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'If you believe this restriction should be reconsidered, you can ask an administrator to review it.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ),
        Text(
          remaining == 1
              ? '1 of $max appeals remaining for this restriction'
              : '$remaining of $max appeals remaining for this restriction',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          'Request an appeal',
          icon: Icons.rate_review_outlined,
          onPressed: canAppeal && !_submitting ? _requestAppeal : null,
        ),
        if (unavailable != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.primaryNavy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unavailable,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AppealCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _AppealCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

class _AppealStatusChip extends StatelessWidget {
  final String? status;
  const _AppealStatusChip(this.status);

  @override
  Widget build(BuildContext context) => RoleChip(switch (status) {
    'pending' => 'Pending',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'closed' => 'Closed',
    _ => 'Unknown',
  }, error: status == 'rejected');
}

/// Collects the appeal explanation. Pops the new appeal status on success, or
/// the error when the state changed elsewhere (already pending, limit reached,
/// account reactivated), so the screen can refresh and explain it.
class AppealDialog extends StatefulWidget {
  const AppealDialog({super.key});
  @override
  State<AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<AppealDialog> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // _busy is set synchronously, so a second tap cannot send a second request.
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await SupabaseService.submitAppeal(_message.text);
      if (mounted) Navigator.pop<Object>(context, status);
    } catch (e) {
      if (!mounted) return;
      const stateCodes = [
        'appeal_pending',
        'appeal_limit_reached',
        'account_active',
      ];
      if (e is PostgrestException && stateCodes.any(e.message.contains)) {
        Navigator.pop<Object>(context, e);
      } else {
        // Network and other failures stay here; Submit again to retry.
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Request an appeal'),
      content: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Explain why your restriction should be reconsidered. An administrator will review your appeal.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            const FieldLabel('Your explanation', requiredField: true),
            ValidatedTextArea(
              controller: _message,
              enabled: !_busy,
              maxLength: 1000,
              validator: validateAppealMessage,
              hintText:
                  'What happened, and why should the restriction be lifted?',
              helperText:
                  "Please don't include health details or other sensitive personal information.",
            ),
            if (_error != null) FieldErrorNotice(_error!),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Submitting...' : 'Submit appeal'),
        ),
      ],
    ),
  );
}
