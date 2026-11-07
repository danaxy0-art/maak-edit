import 'package:flutter/material.dart';
import '../../backend/services/supabase_service.dart';
import 'feedback.dart';
import '../design/tokens.dart';

void showAiMatchingDetails(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    actionsAlignment: MainAxisAlignment.center,
    title: const Text('AI matching details'),
    content: const SingleChildScrollView(
      child: Text(
        'Ma’ak first compares shared chronic conditions. Google Gemini may then compare '
        'your profile description with volunteers’ experience descriptions to improve recommendations. '
        'This applies to both Support Seekers and Volunteers.\n\n'
        'Only the descriptions are sent to Gemini. Names, email addresses, verification '
        'documents, private chat messages, images and voice recordings are not sent. '
        'Avoid identifying information in your description. Descriptions may still contain health information.\n\n'
        'Your agreement and its date are saved to your account. This agreement is required '
        'to complete registration. Matching suggestions are peer support recommendations, '
        'not medical advice or a guarantee of suitability. If AI is unavailable, shared-condition '
        'matching remains available while your AI matching setting is on. You can turn this setting on or off in your profile. When it is off, Support Seekers cannot find new matches and Volunteers do not appear as available for new matches. Existing conversations remain available.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class AiConsentField extends StatelessWidget {
  final bool value, enabled;
  final ValueChanged<bool> onChanged;
  const AiConsentField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => FormField<bool>(
    initialValue: value,
    validator: (_) => value ? null : 'Please agree to AI matching to continue.',
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: enabled
              ? (checked) {
                  field.didChange(checked);
                  onChanged(checked ?? false);
                }
              : null,
          title: const Text('I agree to AI matching. *'),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 12),
          child: OutlinedButton.icon(
            onPressed: () => showAiMatchingDetails(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: MaakColors.ink,
              backgroundColor: MaakColors.selected,
              side: const BorderSide(color: MaakColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(48, 48),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
            icon: const Icon(Icons.info_outline, size: 20),
            label: const Text('AI matching details'),
          ),
        ),
        if (field.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

Future<bool> requestAiMatchingActivation(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      actionsAlignment: MainAxisAlignment.center,
      backgroundColor: MaakColors.surface,
      icon: const Icon(Icons.auto_awesome, color: MaakColors.ink, size: 32),
      title: const Text('Activate AI matching'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Turn on AI matching to find suitable volunteers or appear as an available volunteer. Your profile description may be compared using Gemini.',
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: MaakColors.ink),
            onPressed: () => showAiMatchingDetails(dialogContext),
            icon: const Icon(Icons.info_outline),
            label: const Text(
              'Read details',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: MaakColors.muted),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MaakColors.selected,
            foregroundColor: MaakColors.ink,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Activate'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;
  await SupabaseService.setAiMatchingEnabled(true);
  return true;
}

class AiMatchingSettings extends StatefulWidget {
  const AiMatchingSettings({super.key});
  @override
  State<AiMatchingSettings> createState() => _AiMatchingSettingsState();
}

class _AiMatchingSettingsState extends State<AiMatchingSettings> {
  late Future<bool> _setting;
  bool _busy = false;
  Future<bool> _read() async =>
      await SupabaseService.client.rpc('has_maak_ai_consent') == true;
  void _refresh() {
    if (mounted) {
  setState(() {
    _setting = _read();
  });
}
  }

  @override
  void initState() {
    super.initState();
    _setting = _read();
    SupabaseService.profileRevision.addListener(_refresh);
  }

  @override
  void dispose() {
    SupabaseService.profileRevision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _change(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (enabled) {
        if (!await requestAiMatchingActivation(context)) return;
      } else {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            actionsAlignment: MainAxisAlignment.center,
            title: const Text('Turn off AI matching?'),
            content: const Text(
              'You will not be able to find new matches or appear as an available volunteer until you turn it on again. Your existing chats stay available.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep on'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: MaakColors.selected,
                  foregroundColor: MaakColors.ink,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Turn off'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await SupabaseService.setAiMatchingEnabled(false);
      }
      if (mounted) {
  setState(() {
    _setting = Future.value(enabled);
  });
}
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _setting,
    builder: (context, snapshot) => Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MaakColors.surface,
        border: Border.all(color: MaakColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: MaakColors.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI matching',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MaakColors.ink,
                      ),
                    ),
                    Text(
                      _busy
                          ? 'Saving…'
                          : snapshot.hasError
                          ? 'Could not load setting'
                          : !snapshot.hasData
                          ? 'Loading…'
                          : snapshot.data!
                          ? 'On · Ready for matching'
                          : 'Off · Activate to use matching',
                      style: const TextStyle(
                        fontSize: 12,
                        color: MaakColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: snapshot.data == true,
                onChanged: _busy || !snapshot.hasData ? null : _change,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? MaakColors.ink
                      : MaakColors.muted,
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? MaakColors.selected
                      : MaakColors.fill,
                ),
                trackOutlineColor: WidgetStateProperty.all(MaakColors.border),
              ),
            ],
          ),
          if (snapshot.hasError)
            TextButton(onPressed: _refresh, child: const Text('Retry')),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: MaakColors.ink),
            onPressed: () => showAiMatchingDetails(context),
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text(
              'Matching details',
              style: TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    ),
  );
}
