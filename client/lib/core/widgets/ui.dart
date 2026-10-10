import 'package:flutter/material.dart';

import 'package:astra_client/core/theme/client_theme.dart';

/// Pastille de statut colorée par son ton.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, this.tone = Tone.neutral, this.icon, super.key});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tone.foreground(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background(scheme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre de progression arrondie avec pourcentage.
class ProgressMeter extends StatelessWidget {
  const ProgressMeter({required this.percent, this.showLabel = true, this.height = 8, super.key});

  final int percent;
  final bool showLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = percent.clamp(0, 100) / 100;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, animated, _) => LinearProgressIndicator(
          value: animated,
          minHeight: height,
          color: percent >= 100 ? Tone.success.foreground(scheme) : scheme.primary,
          backgroundColor: scheme.surfaceContainer,
        ),
      ),
    );
    if (!showLabel) return bar;
    return Row(
      children: [
        Expanded(child: bar),
        const SizedBox(width: Space.md),
        SizedBox(
          width: 44,
          child: Text(
            '$percent %',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

/// Carte de section avec titre, action facultative et contenu.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(Space.lg),
    super.key,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                  ?trailing,
                ],
              ),
              const SizedBox(height: Space.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Titre de section hors carte.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Indicateur chiffré cliquable du tableau de bord.
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.tone = Tone.brand,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.background(scheme),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tone.foreground(scheme)),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: text.headlineSmall),
                    Text(
                      label,
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icône carrée teintée, utilisée en tête de ligne.
class ToneIcon extends StatelessWidget {
  const ToneIcon(this.icon, {this.tone = Tone.brand, this.size = 40, super.key});

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.background(scheme),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: tone.foreground(scheme)),
    );
  }
}

/// Ligne « libellé : valeur » des fiches détaillées.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {this.emphasize = false, super.key});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: emphasize
                  ? text.titleMedium
                  : text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marque Astra Client (logo + nom).
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 40, this.showName = true, super.key});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ClientColors.ink, ClientColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Image.asset('assets/branding/astra_mark_white.png', fit: BoxFit.contain),
    );
    if (!showName) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: Space.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ASTRA',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(letterSpacing: 3, fontWeight: FontWeight.w800, height: 1),
            ),
            Text(
              'Espace client',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.primary, letterSpacing: 0.6),
            ),
          ],
        ),
      ],
    );
  }
}

/// Avatar à initiales.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {this.radius = 18, this.tone = Tone.brand, super.key});

  final String initials;
  final double radius;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: tone.background(scheme),
      child: Text(
        initials,
        style: TextStyle(
          color: tone.foreground(scheme),
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
