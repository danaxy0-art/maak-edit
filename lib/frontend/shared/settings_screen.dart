import '../redesign/ui.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BotanicalScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        children: const [
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
          ),
          _SettingsTile(icon: Icons.language_outlined, title: 'Language'),
          _SettingsTile(icon: Icons.lock_outline, title: 'Privacy'),
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            trailingText: 'Light',
          ),
          _SettingsTile(icon: Icons.info_outline, title: "About Ma'ak"),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryNavy),
      title: Text(title, style: const TextStyle(color: AppColors.textDark)),
      trailing: trailingText != null
          ? Text(
              trailingText!,
              style: const TextStyle(color: AppColors.textMuted),
            )
          : const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: () {},
    );
  }
}
