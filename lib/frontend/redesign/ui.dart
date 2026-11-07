import 'package:flutter/material.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/maak_logo.dart';

// Shared building blocks of the original screens. Their names and parameters
// are kept so every screen keeps its structure; their appearance follows the
// redesign tokens (blush canvas, white hairline cards, dark pill buttons).

class ResponsiveBody extends StatelessWidget {
  final Widget child;
  const ResponsiveBody({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: MaakBreakpoints.phoneMaxContent,
      ),
      child: child,
    ),
  );
}

/// Every route shares the blush-to-white canvas. The name is kept from the
/// earlier botanical design so existing screens need no change.
class BotanicalScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body, bottomNavigationBar;
  const BotanicalScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
  });
  // The canvas sits behind the whole Scaffold, so a transparent app bar
  // shares one continuous gradient with the body instead of a flat band.
  @override
  Widget build(BuildContext context) => BlushCanvas(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      body: body,
    ),
  );
}

/// Decorative page background: the blush canvas gradient.
class BotanicalBackdrop extends StatelessWidget {
  final bool subtle;
  const BotanicalBackdrop({super.key, this.subtle = false});
  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: MaakGradients.canvas),
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
  // A minimum rather than a fixed height: the header grows with its content
  // (long titles, large text) instead of overflowing.
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight:
          height * (MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.8)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                child: back && Navigator.canPop(context)
                    ? const RoundIconSurface(child: BackButton())
                    : null,
              ),
              const Expanded(child: MaakLogo(iconSize: 29)),
              const SizedBox(width: 48),
            ],
          ),
          if (progress != null) ...[const SizedBox(height: 16), progress!],
          const SizedBox(height: 25),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: progress == null ? TextAlign.center : TextAlign.start,
              style: MaakText.greeting.copyWith(fontSize: 32, height: 1.1),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: progress == null ? TextAlign.center : TextAlign.start,
            style: MaakText.body.copyWith(color: MaakColors.onHero),
          ),
        ],
      ),
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
    decoration: const BoxDecoration(
      color: MaakColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      border: Border.fromBorderSide(BorderSide(color: MaakColors.border)),
      boxShadow: [
        BoxShadow(
          color: Color(0x14AA6464),
          blurRadius: 20,
          offset: Offset(0, -4),
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
        Icon(Icons.verified_user_outlined, size: 19, color: MaakColors.icon),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            'Your information stays private.',
            style: MaakText.caption,
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
      body: Stack(
        children: [
          // The one restrained glow, spanning the full width behind the
          // centred column so tablets show no hard edge.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight * 1.4,
            child: const ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: AlignmentDirectional.topEnd,
                    radius: 1.2,
                    colors: [
                      MaakColors.orbPink,
                      MaakColors.orbBlush,
                      Color(0x00FEF8F8),
                    ],
                    stops: [0, .4, 1],
                  ),
                ),
              ),
            ),
          ),
          _body(content),
        ],
      ),
    );
  }

  Widget _body(List<Widget> content) => SafeArea(
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
  );
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
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: MaakColors.ink,
      ),
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
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: busy ? null : onPressed,
    child: busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: MaakColors.muted,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(label, textAlign: TextAlign.center)),
              if (icon != null) ...[
                const SizedBox(width: 12),
                Icon(icon, size: 20),
              ],
            ],
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
  Widget build(BuildContext context) =>
      SoftCard(onTap: onTap, padding: padding, child: child);
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: MaakGradients.orb,
      borderRadius: BorderRadius.circular(MaakRadius.hero),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(title, style: MaakText.cardTitle.copyWith(fontSize: 24)),
        ),
        const SizedBox(height: 12),
        Text(subtitle, style: MaakText.body.copyWith(color: MaakColors.onHero)),
        if (button != null) ...[
          const SizedBox(height: 20),
          PillButton(button!, onPressed: onTap, icon: Icons.arrow_forward),
        ],
      ],
    ),
  );
}

class RoleChip extends StatelessWidget {
  final String label;
  final bool error;

  /// Grey style for pending / awaiting states.
  final bool pending;
  const RoleChip(
    this.label, {
    super.key,
    this.error = false,
    this.pending = false,
  });

  // Role badges get their own tint from the Ma'ak palette so volunteers and
  // help seekers are easy to tell apart; every other chip keeps the default.
  static const _volunteer = (
    background: MaakColors.orbPeach, // #FDDFC5
    text: Color(0xFF8A4B1F),
  );
  static const _helpSeeker = (
    background: MaakColors.orbPink, // #FFD3E5
    text: Color(0xFF8E2457),
  );

  @override
  Widget build(BuildContext context) {
    // Error and pending are status styles; they take priority over role tints.
    final role = error || pending
        ? null
        : switch (label) {
            'Volunteer' => _volunteer,
            'Help seeker' => _helpSeeker,
            _ => null,
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: error
            ? const Color(0xFFFDE8E8)
            : pending
            ? MaakColors.pending
            : role?.background ?? MaakColors.selected,
        borderRadius: BorderRadius.circular(MaakRadius.pill),
      ),
      child: Text(
        label,
        style: MaakText.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: error
              ? const Color(0xFFB0222A)
              : role?.text ?? MaakColors.ink,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Semantics(header: true, child: Text(text, style: MaakText.section)),
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
        IconBadge(icon, size: 64),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: MaakText.itemTitle.copyWith(fontSize: 17),
        ),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center, style: MaakText.body),
        if (retry != null) ...[
          const SizedBox(height: 18),
          PillButton('Try again', outlined: true, onPressed: retry),
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

/// Local calendar date such as "20 Oct 2026"; empty when missing or invalid.
String formatDay(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return '';
  final d = parsed.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
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
              backgroundColor: MaakColors.button,
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
        height: 1.5,
        margin: const EdgeInsets.only(bottom: 20),
        color: step == 1 ? MaakColors.button : MaakColors.border,
      ),
      Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: step == 1
                ? MaakColors.button
                : MaakColors.selected,
            child: Text(
              '2',
              style: TextStyle(
                color: step == 1 ? Colors.white : MaakColors.ink,
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
