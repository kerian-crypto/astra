import 'package:flutter/material.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/widgets/ui.dart';

/// Mise en page des écrans de connexion : formulaire seul sur téléphone,
/// panneau de marque + formulaire côte à côte sur tablette et grand écran.
class AuthLayout extends StatelessWidget {
  const AuthLayout({required this.title, required this.subtitle, required this.child, super.key});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final form = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (context.isCompact) ...[
                  const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 48)),
                  const SizedBox(height: 40),
                ],
                Text(title, style: text.headlineMedium),
                const SizedBox(height: Space.sm),
                Text(
                  subtitle,
                  style: text.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.xxl),
                child,
              ],
            ),
          ),
        ),
      ),
    );
    if (context.isCompact) return Scaffold(body: form);
    return Scaffold(
      body: Row(
        children: [
          const Expanded(child: _BrandPanel()),
          Expanded(child: form),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const white70 = Color(0xB3FFFFFF);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [ClientColors.ink, Color(0xFF0B4F5C), ClientColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Theme(
                data: Theme.of(context).copyWith(
                  textTheme: text.apply(bodyColor: Colors.white, displayColor: Colors.white),
                  colorScheme: Theme.of(context).colorScheme.copyWith(primary: ClientColors.amber),
                ),
                child: const BrandMark(size: 52),
              ),
              const Spacer(),
              Text(
                'Votre relation avec Astra,\nen toute clarté.',
                style: text.headlineMedium?.copyWith(color: Colors.white, height: 1.25),
              ),
              const SizedBox(height: Space.xl),
              for (final (icon, label) in const [
                (Icons.timeline_rounded, 'Suivez l\'avancement de vos projets'),
                (Icons.fact_check_outlined, 'Validez vos livrables en un geste'),
                (Icons.receipt_long_outlined, 'Retrouvez vos factures et contrats'),
                (Icons.forum_outlined, 'Échangez directement avec votre équipe'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Row(
                    children: [
                      Icon(icon, color: ClientColors.amber, size: 22),
                      const SizedBox(width: Space.md),
                      Text(label, style: text.bodyLarge?.copyWith(color: white70)),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                'Espace privé et sécurisé · Accès sur invitation',
                style: text.bodySmall?.copyWith(color: white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
