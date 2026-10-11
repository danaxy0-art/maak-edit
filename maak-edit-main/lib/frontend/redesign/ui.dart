import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/maak_logo.dart';

class ResponsiveBody extends StatelessWidget {
  final Widget child;
  const ResponsiveBody({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: child,
    ),
  );
}

/// Every route uses the same image-backed, botanical design language.
class BotanicalScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body, bottomNavigationBar;
  const BotanicalScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    bottomNavigationBar: bottomNavigationBar,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(child: BotanicalBackdrop(subtle: true)),
        if (body != null) body!,
      ],
    ),
  );
}

class BotanicalBackdrop extends StatelessWidget {
  final bool subtle;
  const BotanicalBackdrop({super.key, this.subtle = false});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Image.asset(
        'assets/images/botanical_background.png',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        opacity: AlwaysStoppedAnimation(subtle ? .17 : 1),
      ),
    ),
  );
}

class BotanicalHeader extends StatelessWidget {
  final String title, subtitle;
  final Widget? progress;
  final bool back;
  final double height;
  const BotanicalHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.progress,
    this.back = true,
    this.height = 290,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height * (MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.8)),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/botanical_background.png', fit: BoxFit.fill),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background,
                Color(0xCCF7F3EA),
                Color(0x00F7F3EA),
              ],
              stops: [0, .45, 1],
            ),
          ),
        ),
        if (progress != null)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xB3F7F3EA), Color(0x00F7F3EA)],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: back && Navigator.canPop(context)
                        ? IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back, size: 23),
                          )
                        : null,
                  ),
                  const Expanded(child: MaakLogo(iconSize: 29)),
                  const SizedBox(width: 30),
                ],
              ),
              if (progress != null) ...[const SizedBox(height: 16), progress!],
              const SizedBox(height: 25),
              Text(
                title,
                textAlign: progress == null ? TextAlign.center : TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'MaakSerif',
                  fontSize: 32,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: progress == null ? TextAlign.center : TextAlign.left,
                style: const TextStyle(
                  color: AppColors.primaryNavy,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class FormSheet extends StatelessWidget {
  final Widget child;
  const FormSheet({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDFA),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      border: Border.all(color: const Color(0xFFE8E1D5)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x142C4A66),
          blurRadius: 20,
          offset: Offset(0, -5),
        ),
      ],
    ),
    child: child,
  );
}

class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 18),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user, size: 19, color: AppColors.primaryNavy),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            'Your information stays private.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      ],
    ),
  );
}

class AuthCanvas extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  final bool back, hills;
  final String heroTitle, heroSubtitle;
  final Widget? progress;
  final double heroHeight;
  const AuthCanvas({
    super.key,
    required this.children,
    this.title,
    this.back = true,
    this.hills = true,
    this.heroTitle = 'A little support.\nA stronger you.',
    this.heroSubtitle =
        'Real people. Shared experiences.\nBrighter days ahead.',
    this.progress,
    this.heroHeight = 290,
  });
  @override
  Widget build(BuildContext context) {
    final content = children.where((child) => child is! MaakLogo).toList();
    while (content.isNotEmpty && content.first is SizedBox) {
      content.removeAt(0);
    }
    return BotanicalScaffold(
      body: SafeArea(
        child: ResponsiveBody(
          child: SingleChildScrollView(
            key: ValueKey(heroTitle),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BotanicalHeader(
                  title: heroTitle,
                  subtitle: heroSubtitle,
                  back: back,
                  progress: progress,
                  height: heroHeight,
                ),
                Transform.translate(
                  offset: const Offset(0, -18),
                  child: FormSheet(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: content,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  final bool requiredField;
  const FieldLabel(this.text, {super.key, this.requiredField = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7, top: 16),
    child: Text.rich(
      TextSpan(
        text: text,
        children: [
          if (requiredField)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.error),
            ),
        ],
      ),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  const PrimaryButton(
    this.label, {
    super.key,
    this.onPressed,
    this.busy = false,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(
        colors: onPressed == null || busy
            ? [
                AppColors.primaryNavy.withValues(alpha: .45),
                AppColors.primaryNavy.withValues(alpha: .45),
              ]
            : const [Color(0xFF295677), Color(0xFF163953)],
      ),
    ),
    child: ElevatedButton(
      onPressed: busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(label, textAlign: TextAlign.center)),
                if (icon != null) ...[
                  const SizedBox(width: 14),
                  Icon(icon, size: 20),
                ],
              ],
            ),
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDFA),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.fieldBorder.withValues(alpha: .65)),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryNavy.withValues(alpha: .035),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class LandscapeHills extends StatelessWidget {
  final bool detailed;
  const LandscapeHills({super.key, this.detailed = false});
  @override
  Widget build(BuildContext context) => const BotanicalBackdrop();
}

class HeroCard extends StatelessWidget {
  final String title, subtitle;
  final String? button;
  final VoidCallback? onTap;
  const HeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.button,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Container(
      color: const Color(0xFFDCE8F5),
      child: Stack(
        children: [
          const Positioned.fill(child: BotanicalBackdrop()),
          const Positioned.fill(child: ColoredBox(color: Color(0xBBF7F3EA))),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'MaakSerif',
                      fontSize: 28,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
                if (button != null) ...[
                  const SizedBox(height: 20),
                  PrimaryButton(
                    button!,
                    onPressed: onTap,
                    icon: Icons.arrow_forward,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class RoleChip extends StatelessWidget {
  final String label;
  final bool error;
  const RoleChip(this.label, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFEBEB) : AppColors.selectedCardFill,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: error ? AppColors.error : AppColors.primaryNavy,
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontFamily: 'MaakSerif', fontSize: 21),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? retry;
  const EmptyState(
    this.title,
    this.subtitle, {
    super.key,
    this.icon = Icons.inbox_outlined,
    this.retry,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(26),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: AppColors.selectedCardBorder),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        if (retry != null) ...[
          const SizedBox(height: 18),
          OutlinedButton(onPressed: retry, child: const Text('Try again')),
        ],
      ],
    ),
  );
}

class LogoHeader extends StatelessWidget {
  final Widget? trailing;
  const LogoHeader({super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const MaakLogo(iconSize: 26),
      const Spacer(),
      if (trailing != null) trailing!,
    ],
  );
}

String initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .take(2)
    .map((s) => s[0])
    .join()
    .toUpperCase();

class RegistrationProgress extends StatelessWidget {
  final int step;
  final VoidCallback? onAccountTap;
  const RegistrationProgress({
    super.key,
    required this.step,
    this.onAccountTap,
  });
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      InkWell(
        onTap: onAccountTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primaryNavy,
              child: step == 1
                  ? const Icon(Icons.check, color: Colors.white, size: 17)
                  : const Text(
                      '1',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
            ),
            const SizedBox(height: 6),
            const Text('Account', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      Container(
        width: 84,
        height: 1,
        margin: const EdgeInsets.only(bottom: 20),
        color: AppColors.selectedCardBorder,
      ),
      Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: step == 1
                ? AppColors.primaryNavy
                : AppColors.selectedCardFill,
            child: Text(
              '2',
              style: TextStyle(
                color: step == 1 ? Colors.white : AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Preferences', style: TextStyle(fontSize: 12)),
        ],
      ),
    ],
  );
}
