import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/layout/responsive.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/clients/data/brief.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';
import 'package:astra_hub/features/clients/presentation/payment_review_sheet.dart';

/// Espace clients (managers et administrateurs) : entreprises, cahiers des
/// charges, échanges, demandes de support et paiements à vérifier.
class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Espace clients'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.apartment_outlined), text: 'Entreprises'),
              Tab(icon: Icon(Icons.assignment_outlined), text: 'Cahiers des charges'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'Messages'),
              Tab(icon: Icon(Icons.support_agent_outlined), text: 'Support'),
              Tab(icon: Icon(Icons.payments_outlined), text: 'Paiements'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CompaniesTab(),
            _BriefsTab(),
            _ConversationsTab(),
            _TicketsTab(),
            _PaymentsTab(),
          ],
        ),
      ),
    );
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.onRefresh, required this.children, this.empty});

  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final gutter = Breakpoints.gutter(context);
    return ResponsiveCenter(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: children.isEmpty && empty != null
            ? ListView(children: [SizedBox(height: 360, child: empty)])
            : ListView(padding: EdgeInsets.all(gutter), children: children),
      ),
    );
  }
}

class _CompaniesTab extends ConsumerWidget {
  const _CompaniesTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final sector = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle entreprise cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email (facultatif)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sector,
              decoration: const InputDecoration(labelText: 'Secteur (facultatif)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Créer')),
        ],
      ),
    );
    if (created != true || name.text.trim().isEmpty) return;
    try {
      final company = await ref.read(clientsRepositoryProvider).createCompany({
        'name': name.text.trim(),
        if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
        if (sector.text.trim().isNotEmpty) 'sector': sector.text.trim(),
      });
      ref.invalidate(clientCompaniesProvider);
      if (context.mounted) await context.push(Routes.clientCompany(company.id));
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(clientCompaniesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-company',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Entreprise'),
      ),
      body: AsyncValueView(
        value: companies,
        onRetry: () => ref.invalidate(clientCompaniesProvider),
        data: (list) => _Framed(
          onRefresh: () => ref.refresh(clientCompaniesProvider.future),
          empty: const EmptyState(
            icon: Icons.apartment_outlined,
            message: 'Aucune entreprise cliente.',
          ),
          children: [
            if (list.isNotEmpty)
              ResponsiveGrid(
                minItemWidth: 340,
                children: [
                  for (final company in list)
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          backgroundColor: AstraTheme.primary.withValues(alpha: 0.2),
                          child: Text(company.name.substring(0, 1).toUpperCase()),
                        ),
                        title: Text(company.name),
                        subtitle: Text(
                          '${company.projectCount} projet(s) · ${company.accountCount} compte(s)'
                          '${company.sector != null ? ' · ${company.sector}' : ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.clientCompany(company.id)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BriefsTab extends ConsumerWidget {
  const _BriefsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefs = ref.watch(hubBriefsProvider);
    return AsyncValueView(
      value: briefs,
      onRetry: () => ref.invalidate(hubBriefsProvider),
      data: (list) => _Framed(
        onRefresh: () => ref.refresh(hubBriefsProvider.future),
        empty: const EmptyState(
          icon: Icons.assignment_outlined,
          message:
              'Aucun cahier des charges reçu.\nLes clients le remplissent depuis Astra Client.',
        ),
        children: [
          for (final brief in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: const Icon(Icons.assignment_outlined),
                title: Text(brief.title),
                subtitle: Text(
                  '${brief.companyName}${brief.companySelfRegistered ? ' · prospect' : ''}'
                  '${brief.submittedAt != null ? ' · reçu ${relativeDay(brief.submittedAt!)}' : ''}',
                ),
                trailing: Pill(brief.status.label, color: brief.status.color),
                onTap: () => context.push(Routes.clientBrief(brief.id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationsTab extends ConsumerWidget {
  const _ConversationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(clientConversationsProvider);
    return AsyncValueView(
      value: conversations,
      onRetry: () => ref.invalidate(clientConversationsProvider),
      data: (list) => _Framed(
        onRefresh: () => ref.refresh(clientConversationsProvider.future),
        empty: const EmptyState(
          icon: Icons.forum_outlined,
          message: 'Aucun échange avec les clients.',
        ),
        children: [
          for (final c in list)
            ListTile(
              leading: Badge(
                isLabelVisible: c.unreadCount > 0,
                label: Text('${c.unreadCount}'),
                child: const CircleAvatar(child: Icon(Icons.forum_outlined, size: 20)),
              ),
              title: Text(
                '${c.companyName} · ${c.subject}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                c.lastMessage == null
                    ? (c.projectName ?? 'Nouvelle conversation')
                    : '${c.lastMessage!.authorName} : ${c.lastMessage!.body}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(formatShortMoment(c.lastMessageAt ?? c.createdAt)),
              onTap: () => context.push(Routes.clientConversation(c.id)),
            ),
        ],
      ),
    );
  }
}

class _TicketsTab extends ConsumerWidget {
  const _TicketsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(clientTicketsProvider);
    return AsyncValueView(
      value: tickets,
      onRetry: () => ref.invalidate(clientTicketsProvider),
      data: (list) => _Framed(
        onRefresh: () => ref.refresh(clientTicketsProvider.future),
        empty: const EmptyState(
          icon: Icons.support_agent_outlined,
          message: 'Aucune demande de support.',
        ),
        children: [
          for (final t in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                title: Text('#${t.number} · ${t.subject}'),
                subtitle: Text(
                  '${t.companyName} · ${t.priority.label}'
                  '${t.assigneeName != null ? ' · ${t.assigneeName}' : ' · non assigné'}',
                ),
                trailing: Pill(t.status.label, color: ticketColor(t.status)),
                onTap: () => context.push(Routes.clientTicket(t.id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final declarations = ref.watch(pendingDeclarationsProvider);
    return AsyncValueView(
      value: declarations,
      onRetry: () => ref.invalidate(pendingDeclarationsProvider),
      data: (list) {
        final pending = list.where((d) => d.isPending).toList();
        final done = list.where((d) => !d.isPending).toList();
        return _Framed(
          onRefresh: () => ref.refresh(pendingDeclarationsProvider.future),
          empty: const EmptyState(
            icon: Icons.payments_outlined,
            message: 'Aucun paiement déclaré.',
          ),
          children: [
            if (pending.isNotEmpty) ...[
              ListSectionTitle('À vérifier (${pending.length})'),
              for (final d in pending) _DeclarationTile(declaration: d),
            ],
            if (done.isNotEmpty) ...[
              const ListSectionTitle('Traités'),
              for (final d in done.take(50)) _DeclarationTile(declaration: d),
            ],
          ],
        );
      },
    );
  }
}

class _DeclarationTile extends ConsumerWidget {
  const _DeclarationTile({required this.declaration});

  final PaymentDeclaration declaration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = declaration;
    final statusLabel = switch (d.status) {
      'declared' => 'Déclaré',
      'under_review' => 'En vérification',
      'confirmed' => 'Confirmé',
      _ => 'Refusé',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        title: Text('${d.companyName} · ${formatMoney(d.amount, d.currency)}'),
        subtitle: Text(
          'Facture ${d.invoiceNumber} · ${paymentMethodLabels[d.method] ?? d.method} · '
          'payé le ${formatDate(d.paidOn)}${d.reference != null ? ' · réf. ${d.reference}' : ''}',
        ),
        trailing: Pill(
          statusLabel,
          color: paymentColor(d.status == 'declared' ? 'payment_declared' : d.status),
        ),
        onTap: d.isPending ? () => showPaymentReviewSheet(context, d) : null,
      ),
    );
  }
}
