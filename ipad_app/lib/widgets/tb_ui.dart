import 'package:flutter/material.dart';

import '../theme/tb_theme.dart';

class TbBackdrop extends StatelessWidget {
  final Widget child;
  const TbBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111319), TbColors.ink, Color(0xFF151017)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}

class TbWordmark extends StatelessWidget {
  final bool compact;
  const TbWordmark({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 10 : 12,
          height: compact ? 10 : 12,
          decoration: const BoxDecoration(
            color: TbColors.gold,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'TERABOOTH',
          style: TextStyle(
            color: TbColors.cream,
            fontWeight: FontWeight.w900,
            letterSpacing: compact ? 2.0 : 3.0,
            fontSize: compact ? 13 : 15,
          ),
        ),
      ],
    );
  }
}

class TbPageHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;

  const TbPageHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBack)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                TbEyebrow(eyebrow!),
                const SizedBox(height: 8),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 16),
          Wrap(spacing: 10, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

class TbCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final VoidCallback? onTap;

  const TbCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(TbSpace.lg),
    this.color = TbColors.surface,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(TbRadius.lg),
        border: Border.all(
          color: borderColor ?? TbColors.line.withValues(alpha: 0.7),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TbRadius.lg),
      child: card,
    );
  }
}

class TbEyebrow extends StatelessWidget {
  final String text;
  const TbEyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: TbColors.gold,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.2,
      ),
    );
  }
}

class TbPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  const TbPill({
    super.key,
    required this.label,
    this.color = TbColors.gold,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class TbSectionLabel extends StatelessWidget {
  final String text;
  const TbSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: TbColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.8,
      ),
    );
  }
}

class TbPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  const TbPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class TbSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  const TbSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 19),
            label: Text(label),
          );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class TbMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const TbMetric({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TbSectionLabel(label),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: valueColor ?? TbColors.cream,
          ),
        ),
      ],
    );
  }
}

class TbEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const TbEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: TbColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: TbColors.gold),
        ),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    );
  }
}
