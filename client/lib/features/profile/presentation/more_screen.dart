import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/auth/data/session.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';

class _MenuEntry {
  const _MenuEntry(
    this.icon,
    this.label,
    this.subtitle,
    this.route, {
    this.permission,
    this.tone = Tone.brand,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String route;
  final ClientPermission? permission;
  final Tone tone;
}

const _finance = [
  _MenuEntry(
    Icons.receipt_long_outlined,
    'Factures',
    'Montants, échéances, déclarations',
    Routes.invoices,
    permission: ClientPermission.viewInvoice,
    tone: Tone.info,
  ),
  _MenuEntry(
    Icons.history_rounded,
    'Paiements',
    'Historique et vérifications',
    Routes.payments,
    permission: ClientPermission.viewInvoice,
    tone: Tone.info,
  ),
  _MenuEntry(
    Icons.handshake_outlined,
    'Contrats',
    'Prestations, dates, documents',
    Routes.contracts,
    permission: ClientPermission.viewContract,
    tone: Tone.info,
  ),
];

const _service = [
  _MenuEntry(
    Icons.assignment_outlined,
    'Cahiers des charges',
    'Décrire un nouveau projet',
    Routes.briefs,
    permission: ClientPermission.submitBrief,
  ),
  _MenuEntry(
    Icons.support_agent_outlined,
    'Support',
    'Vos demandes et leur suivi',
    Routes.tickets,
    permission: ClientPermission.createTicket,
  ),
  _MenuEntry(
    Icons.notifications_none_rounded,
    'Notifications',
    'Toutes vos alertes',
    Routes.notifications,
  ),
];

const _account = [
  _MenuEntry(
    Icons.person_outline_rounded,
    'Mon profil',
    'Nom, fonction, téléphone',
    Routes.profile,
    tone: Tone.neutral,
  ),
  _MenuEntry(
    Icons.apartment_rounded,
    'Mon entreprise',
    'Coordonnées de l\'entreprise',
    Routes.company,
    tone: Tone.neutral,
  ),
  _MenuEntry(
    Icons.groups_outlined,
    'Utilisateurs',
    'Les comptes de votre entreprise',
    Routes.team,
    permission: ClientPermission.manageCompanyUsers,
    tone: Tone.neutral,
  ),
  _MenuEntry(
    Icons.lock_outline_rounded,
    'Sécurité',
    'Mot de passe et session',
    Routes.security,
    tone: Tone.neutral,
  ),
];

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    List<_MenuEntry> allowed(List<_MenuEntry> entries) =>
        entries.where((e) => e.permission == null || session.can(e.permission!)).toList();
    final sections = [
      ('Finance', allowed(_finance)),
      ('Services', allowed(_service)),
      ('Compte', allowed(_account)),
    ].where((section) => section.$2.isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: const Text('Plus')),
      body: FramedListView(
        maxWidth: 960,
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(Space.lg),
              leading: InitialsAvatar(initials(session.fullName), radius: 26),
              title: Text(session.fullName, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text([session.company.name, ?session.jobTitle].join(' · ')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.profile),
            ),
          ),
          for (final (title, entries) in sections) ...[
            SectionHeader(title),
            ResponsiveGrid(
              minItemWidth: 300,
              spacing: Space.sm,
              children: [
                for (final entry in entries)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Space.lg,
                        vertical: Space.xs,
                      ),
                      leading: ToneIcon(entry.icon, tone: entry.tone),
                      title: Text(entry.label),
                      subtitle: Text(entry.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(entry.route),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.xl),
          Center(
            child: Text(
              'Astra Client · votre espace privé chez Astra',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
