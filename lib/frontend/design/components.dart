import 'package:flutter/material.dart';

import 'tokens.dart';
import '../widgets/user_photo.dart';

// Building blocks for the redesigned screens. Every padding and alignment is
// directional so layouts mirror correctly in right-to-left locales.

/// Blush-to-white page background from the reference.
class BlushCanvas extends StatelessWidget {
  final Widget child;
  const BlushCanvas({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: MaakGradients.canvas),
    child: child,
  );
}

/// White card with the approved hairline border and soft shadow.
class SoftCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// No shadow: for quieter, secondary items such as past requests.
  final bool flat;
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(MaakSpace.lg),
    this.color = MaakColors.surface,
    this.flat = false,
  });
  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MaakRadius.card),
      side: const BorderSide(color: MaakColors.border),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MaakRadius.card),
        boxShadow: flat ? null : MaakShadows.card,
      ),
      child: Material(
        color: color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Icon on a blush circle, used to lead rows, tiles and empty states.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  const IconBadge(
    this.icon, {
    super.key,
    this.size = 40,
    this.color = MaakColors.blush,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Icon(icon, size: size * .5, color: MaakColors.icon),
  );
}

/// 48 pt white circle around an existing icon button, such as the bell.
class RoundIconSurface extends StatelessWidget {
  final Widget child;
  const RoundIconSurface({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: MaakColors.surface,
      shape: BoxShape.circle,
      border: Border.all(color: MaakColors.border),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: MaakColors.icon),
        ),
      ),
      child: IconTheme.merge(
        data: const IconThemeData(size: 24),
        child: Center(child: child),
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  final String text;
  final double top;
  const SectionHeader(this.text, {super.key, this.top = MaakSpace.xxl});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(top: top, bottom: MaakSpace.md),
    child: Semantics(header: true, child: Text(text, style: MaakText.section)),
  );
}

/// Small blush label, e.g. the Volunteer role.
class SoftChip extends StatelessWidget {
  final String label;
  final Color color;
  const SoftChip(this.label, {super.key, this.color = MaakColors.selected});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.symmetric(
      horizontal: MaakSpace.md,
      vertical: 6,
    ),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(MaakRadius.pill),
    ),
    child: Text(
      label,
      style: MaakText.caption.copyWith(
        color: MaakColors.ink,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Dark filled or outlined pill. Shrinks to its label unless [expand].
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined, expand, busy;

  /// 44 pt tall with tighter padding, for actions inside cards.
  final bool compact;
  const PillButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.outlined = false,
    this.expand = false,
    this.busy = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final foreground = outlined ? MaakColors.ink : Colors.white;
    final content = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: MaakColors.muted,
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: compact
                      ? MaakText.button.copyWith(fontSize: 14)
                      : MaakText.button,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: MaakSpace.sm),
                Icon(icon, size: compact ? 16 : 18),
              ],
            ],
          );
    // Disabled buttons turn neutral grey with muted text (6.3:1) instead of a
    // faded black, so "Request sent" style states stay readable.
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(64, compact ? 44 : 48)),
      padding: WidgetStatePropertyAll(
        EdgeInsetsDirectional.symmetric(
          horizontal: compact ? MaakSpace.lg : 22,
          vertical: compact ? MaakSpace.sm : MaakSpace.md,
        ),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? MaakColors.muted
            : foreground,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => outlined
            ? MaakColors.surface
            : states.contains(WidgetState.disabled)
            ? MaakColors.fill
            : MaakColors.button,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => !outlined
            ? BorderSide.none
            : BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? MaakColors.border
                    : MaakColors.button,
                width: 1.5,
              ),
      ),
      elevation: const WidgetStatePropertyAll(0),
    );
    final button = TextButton(
      onPressed: busy ? null : onPressed,
      style: style,
      child: content,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The one gradient card on a screen: title, supporting line, one action.
class GlowActionCard extends StatelessWidget {
  final String title, subtitle, action;
  final VoidCallback onPressed;

  /// Roomier padding and type for tablet widths.
  final bool large;
  const GlowActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
    this.large = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(large ? MaakSpace.xxxl - 4 : MaakSpace.xl),
    decoration: BoxDecoration(
      gradient: MaakGradients.orb,
      borderRadius: BorderRadius.circular(MaakRadius.hero),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      // No max-width boxes here: IntrinsicHeight measures through them at the
      // full width and would under-size the card in the tablet row.
      children: [
        Text(
          title,
          style: large
              ? MaakText.cardTitle.copyWith(fontSize: 24)
              : MaakText.cardTitle,
        ),
        const SizedBox(height: MaakSpace.sm),
        Text(
          subtitle,
          style: MaakText.body.copyWith(
            color: MaakColors.onHero,
            fontSize: large ? 15 : null,
          ),
        ),
        SizedBox(height: large ? MaakSpace.xxl : MaakSpace.lg),
        PillButton(action, icon: Icons.arrow_forward, onPressed: onPressed),
      ],
    ),
  );
}

/// Tappable shortcut: icon, title, supporting text and a chevron. A row on
/// phones; [stacked] puts the icon above the text for tablet grids.
class ActionRow extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool stacked;
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.stacked = false,
  });
  @override
  Widget build(BuildContext context) => stacked ? _tile() : _row();

  Widget _tile() => SoftCard(
    onTap: onTap,
    padding: const EdgeInsets.all(MaakSpace.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon, size: 48),
            const Spacer(),
            const Icon(Icons.chevron_right, color: MaakColors.muted),
          ],
        ),
        const SizedBox(height: MaakSpace.xl),
        Text(title, style: MaakText.itemTitle.copyWith(fontSize: 16)),
        const SizedBox(height: MaakSpace.xs),
        Text(subtitle, style: MaakText.body),
      ],
    ),
  );

  Widget _row() => SoftCard(
    onTap: onTap,
    padding: const EdgeInsetsDirectional.fromSTEB(
      MaakSpace.md,
      MaakSpace.md,
      MaakSpace.sm,
      MaakSpace.md,
    ),
    child: Row(
      children: [
        IconBadge(icon),
        const SizedBox(width: MaakSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: MaakText.itemTitle),
              const SizedBox(height: 2),
              Text(subtitle, style: MaakText.body.copyWith(fontSize: 13)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: MaakColors.muted),
      ],
    ),
  );
}

class InitialsAvatar extends StatelessWidget {
  final String initials;

  /// When set, that user's profile picture replaces the initials.
  final String? userId;
  const InitialsAvatar(this.initials, {super.key, this.userId});
  @override
  Widget build(BuildContext context) => userId == null
      ? _circle()
      : UserPhoto(userId: userId, size: 48, child: _circle());

  Widget _circle() => Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: MaakColors.blush,
      shape: BoxShape.circle,
    ),
    // Shrinks with large text instead of spilling out of the circle.
    child: Padding(
      padding: const EdgeInsets.all(MaakSpace.sm),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(initials, style: MaakText.itemTitle.copyWith(fontSize: 16)),
      ),
    ),
  );
}

/// A person and their latest message, e.g. the most recent conversation.
class PersonPreviewCard extends StatelessWidget {
  final String initials, name, message;
  final VoidCallback onTap;

  /// When set, that user's profile picture replaces the initials.
  final String? userId;
  const PersonPreviewCard({
    super.key,
    this.userId,
    required this.initials,
    required this.name,
    required this.message,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => SoftCard(
    onTap: onTap,
    padding: const EdgeInsetsDirectional.fromSTEB(
      MaakSpace.lg,
      MaakSpace.lg,
      MaakSpace.sm,
      MaakSpace.lg,
    ),
    child: Row(
      children: [
        InitialsAvatar(initials, userId: userId),
        const SizedBox(width: MaakSpace.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: MaakText.itemTitle),
              const SizedBox(height: MaakSpace.xs),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MaakText.body.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: MaakColors.muted),
      ],
    ),
  );
}

class StatTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: SoftCard(
      padding: const EdgeInsets.all(MaakSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon, size: 32),
              const SizedBox(width: MaakSpace.sm),
              Expanded(child: Text(label, style: MaakText.caption)),
            ],
          ),
          const SizedBox(height: MaakSpace.md),
          Text('$value', style: MaakText.number),
        ],
      ),
    ),
  );
}

/// Inline empty or error message inside a section, with optional retry.
class StateMessage extends StatelessWidget {
  final String? title;
  final String message;
  final IconData icon;
  final VoidCallback? retry;
  const StateMessage({
    super.key,
    this.title,
    required this.message,
    required this.icon,
    this.retry,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(MaakSpace.lg),
    decoration: BoxDecoration(
      color: MaakColors.warmWhite,
      borderRadius: BorderRadius.circular(MaakRadius.card),
      border: Border.all(color: MaakColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(icon, color: MaakColors.fill),
        const SizedBox(width: MaakSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title!, style: MaakText.itemTitle),
                const SizedBox(height: MaakSpace.xs),
              ],
              Text(message, style: MaakText.body),
              if (retry != null) ...[
                const SizedBox(height: MaakSpace.md),
                PillButton('Try again', outlined: true, onPressed: retry),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Static placeholder in the shape of content that is still loading.
class SkeletonBlock extends StatelessWidget {
  final double height;
  const SkeletonBlock({super.key, required this.height});
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: MaakColors.fill,
      borderRadius: BorderRadius.circular(MaakRadius.card),
    ),
  );
}

/// Title row of a redesigned page: a back button when the route can be
/// popped, the title, then optional actions in round buttons.
class PageHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const PageHeader(this.title, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (Navigator.canPop(context)) ...[
        const RoundIconSurface(child: BackButton()),
        const SizedBox(width: MaakSpace.md),
      ],
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: MaakText.pageTitle),
        ),
      ),
      for (final action in actions)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: MaakSpace.sm),
          child: RoundIconSurface(child: action),
        ),
    ],
  );
}

/// Scaffold for redesigned pages: blush canvas, a page header and a content
/// column sized for phones or tablets, with an optional pinned bottom bar.
class MaakPage extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> Function(BuildContext context, bool wide) children;
  final Widget? Function(bool wide)? bottomBar;
  final Future<void> Function()? onRefresh;
  const MaakPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.bottomBar,
    this.onRefresh,
  });

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= MaakBreakpoints.tablet;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final gutter = wide ? MaakSpace.xxl : MaakSpace.lg;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        MaakSpace.sm,
        gutter,
        MaakSpace.xxxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide
                  ? MaakBreakpoints.tabletMaxContent
                  : MaakBreakpoints.phoneMaxContent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(title, actions: actions),
                const SizedBox(height: MaakSpace.xl),
                ...children(context, wide),
              ],
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: MaakColors.canvasMid,
      bottomNavigationBar: bottomBar?.call(wide),
      body: BlushCanvas(
        child: SafeArea(
          bottom: false,
          child: onRefresh == null
              ? list
              : RefreshIndicator(
                  onRefresh: onRefresh!,
                  color: MaakColors.ink,
                  child: list,
                ),
        ),
      ),
    );
  }
}

/// Search input with the hairline border, a clear button once text is
/// entered, and no visible character counter ([maxLength] still applies).
class MaakSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final int? maxLength;
  const MaakSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.maxLength,
  });
  @override
  State<MaakSearchField> createState() => _MaakSearchFieldState();
}

class _MaakSearchFieldState extends State<MaakSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: _controller,
      maxLength: widget.maxLength,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      onChanged: _changed,
      textInputAction: TextInputAction.search,
      style: MaakText.body.copyWith(color: MaakColors.ink, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: MaakText.body.copyWith(fontSize: 15),
        filled: true,
        fillColor: MaakColors.surface,
        isDense: false,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: MaakSpace.lg,
          vertical: 14,
        ),
        prefixIcon: const Icon(Icons.search, color: MaakColors.muted),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, color: MaakColors.muted),
                onPressed: () {
                  _controller.clear();
                  _changed('');
                },
              ),
        border: border(MaakColors.border),
        enabledBorder: border(MaakColors.border),
        focusedBorder: border(MaakColors.button, 1.5),
      ),
    );
  }
}

/// A condition name. [shared] marks one the member also lives with.
class ConditionChip extends StatelessWidget {
  final String label;
  final bool shared;
  const ConditionChip(this.label, {super.key, this.shared = false});
  @override
  Widget build(BuildContext context) => Semantics(
    label: shared ? '$label, shared with you' : label,
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: shared ? MaakColors.selected : MaakColors.fill,
        borderRadius: BorderRadius.circular(MaakRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shared) ...[
            const Icon(Icons.check, size: 14, color: MaakColors.ink),
            const SizedBox(width: MaakSpace.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: MaakText.caption.copyWith(color: MaakColors.ink),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Icon plus text, so a status never relies on colour alone.
class StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const StatusPill({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 11, 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(MaakRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: MaakColors.ink),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: MaakText.caption.copyWith(
              color: MaakColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Small icon and text line, such as a volunteer's language.
class MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const MetaLine({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: MaakColors.muted),
      const SizedBox(width: 6),
      Flexible(child: Text(text, style: MaakText.body.copyWith(fontSize: 13))),
    ],
  );
}

/// Placeholder cards while a list loads, announced as [label].
class ListSkeleton extends StatelessWidget {
  final String label;
  final int count;
  final double height;
  const ListSkeleton({
    super.key,
    required this.label,
    this.count = 3,
    this.height = 112,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: MaakSpace.md),
          SkeletonBlock(height: height),
        ],
      ],
    ),
  );
}

/// Keeps a page's main action in view at the bottom of the screen.
class StickyActionBar extends StatelessWidget {
  final Widget child;
  const StickyActionBar({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: MaakColors.warmWhite,
      border: Border(top: BorderSide(color: MaakColors.border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MaakSpace.lg,
          MaakSpace.md,
          MaakSpace.lg,
          MaakSpace.md,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: MaakBreakpoints.phoneMaxContent,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Two columns whose cards share a height row by row.
class PairedGrid extends StatelessWidget {
  final List<Widget> children;
  const PairedGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: MaakSpace.md),
        // A lone last card is centred at the same width as the others,
        // instead of sitting in the left column next to an empty one.
        if (i + 1 == children.length)
          LayoutBuilder(
            builder: (context, constraints) => Center(
              child: SizedBox(
                width: (constraints.maxWidth - MaakSpace.md) / 2,
                child: children[i],
              ),
            ),
          )
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: MaakSpace.md),
                Expanded(child: children[i + 1]),
              ],
            ),
          ),
      ],
    ],
  );
}

/// Condition names from a comma-separated list, as browse_volunteers sends.
List<String> conditionNames(Object? value) => '${value ?? ''}'
    .split(',')
    .map((name) => name.trim())
    .where((name) => name.isNotEmpty)
    .toList();
