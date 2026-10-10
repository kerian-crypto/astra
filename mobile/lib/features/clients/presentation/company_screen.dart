import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/layout/responsive.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/clients/data/clients.dart';
import 'package:astra_hub/features/clients/data/clients_repository.dart';
import 'package:astra_hub/features/clients/presentation/client_widgets.dart';

/// Fiche d'une entreprise cliente : comptes et accès, factures, contrats.
class CompanyScreen extends ConsumerWidget {
  const CompanyScreen({required this.companyId, super.key});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(clientCompanyProvider(companyId));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(company.value?.name ?? 'Entreprise'),
          actions: [
            IconButton(
              tooltip: 'Écrire au client',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => _startConversation(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Comptes'),
              Tab(text: 'Factures'),
              Tab(text: 'Contrats'),
            ],
          ),
        ),
        body: AsyncValueView(
          value: company,
          onRetry: () => ref.invalidate(clientCompanyProvider(companyId)),
          data: (c) => TabBarView(
            children: [
              _AccountsTab(company: c),
              _InvoicesTab(company: c),
              _ContractsTab(company: c),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startConversation(BuildContext context, WidgetRef ref) async {
    final subject = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau message au client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subject,
              decoration: const InputDecoration(labelText: 'Sujet'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok != true || subject.text.trim().isEmpty || body.text.trim().isEmpty) return;
    try {
      final conversation = await ref
          .read(clientsRepositoryProvider)
          .startConversation(companyId: companyId, subject: subject.text, body: body.text);
      ref.invalidate(clientConversationsProvider);
      if (context.mounted) await context.push(Routes.clientConversation(conversation.id));
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }
}

class _AccountsTab extends ConsumerWidget {
  const _AccountsTab({required this.company});

  final ClientCompany company;

  Future<void> _addAccount(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String, String, Set<ClientPermission>)>(
      context: context,
      builder: (_) => const _AccountDialog(),
    );
    if (result == null) return;
    final (email, name, job, permissions) = result;
    try {
      final (account, invitation) = await ref
          .read(clientsRepositoryProvider)
          .createAccount(
            company.id,
            email: email,
            fullName: name,
            jobTitle: job,
            permissions: permissions,
          );
      ref.invalidate(clientAccountsProvider(company.id));
      if (context.mounted) await showInvitationDialog(context, invitation, account.fullName);
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  Future<void> _editPermissions(BuildContext context, WidgetRef ref, ClientAccount account) async {
    final selected = await showDialog<Set<ClientPermission>>(
      context: context,
      builder: (_) => _PermissionsDialog(initial: account.permissions),
    );
    if (selected == null) return;
    try {
      await ref.read(clientsRepositoryProvider).updateAccount(account.id, {
        'permissions': [for (final p in selected) p.value],
      });
      ref.invalidate(clientAccountsProvider(company.id));
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(clientAccountsProvider(company.id));
    final gutter = Breakpoints.gutter(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-account',
        onPressed: () => _addAccount(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Inviter'),
      ),
      body: AsyncValueView(
        value: accounts,
        onRetry: () => ref.invalidate(clientAccountsProvider(company.id)),
        data: (list) => ResponsiveCenter(
          maxWidth: Breakpoints.readingMaxWidth,
          child: ListView(
            padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 96),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.apartment_outlined),
                  title: Text(company.name),
                  subtitle: Text(
                    [
                      ?company.email,
                      ?company.phone,
                      ?company.sector,
                      '${company.projectCount} projet(s)',
                    ].join(' · '),
                  ),
                ),
              ),
              if (company.internalNotes != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline, color: AstraTheme.warning),
                    title: const Text('Note interne (jamais visible du client)'),
                    subtitle: Text(company.internalNotes!),
                  ),
                ),
              ListSectionTitle('Comptes (${list.length})'),
              if (list.isEmpty)
                const Text('Invitez un premier interlocuteur pour lui ouvrir Astra Client.'),
              for (final account in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    title: Text(account.fullName),
                    subtitle: Text(
                      '${account.email}\n'
                      '${account.isActivated ? 'Activé · dernière connexion ${account.lastLoginAt != null ? relativeDay(account.lastLoginAt!) : '—'}' : 'Invitation en attente'}'
                      ' · ${account.permissions.length} droit(s)',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        final repository = ref.read(clientsRepositoryProvider);
                        try {
                          switch (action) {
                            case 'link':
                              final link = await repository.reissueInvitation(account.id);
                              if (context.mounted) {
                                await showInvitationDialog(context, link, account.fullName);
                              }
                            case 'permissions':
                              await _editPermissions(context, ref, account);
                            case 'toggle':
                              await repository.updateAccount(account.id, {
                                'is_active': !account.isActive,
                              });
                              ref.invalidate(clientAccountsProvider(company.id));
                          }
                        } on Exception catch (error) {
                          if (context.mounted) showMessage(context, error);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'link',
                          child: Text(
                            account.isActivated
                                ? 'Lien de nouveau mot de passe'
                                : 'Nouveau lien d\'activation',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'permissions',
                          child: Text('Modifier les droits'),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(
                            account.isActive ? 'Désactiver l\'accès' : 'Réactiver l\'accès',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _job = TextEditingController();
  Set<ClientPermission> _permissions = {...ClientPermission.defaults};

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _job.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Inviter un interlocuteur'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom complet'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _job,
              decoration: const InputDecoration(labelText: 'Fonction (facultatif)'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Droits'),
              subtitle: Text('${_permissions.length} sélectionné(s)'),
              trailing: const Icon(Icons.tune),
              onTap: () async {
                final selected = await showDialog<Set<ClientPermission>>(
                  context: context,
                  builder: (_) => _PermissionsDialog(initial: _permissions),
                );
                if (selected != null) setState(() => _permissions = selected);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty || !_email.text.contains('@')) return;
            Navigator.pop(context, (
              _email.text.trim(),
              _name.text.trim(),
              _job.text.trim(),
              _permissions,
            ));
          },
          child: const Text('Créer le lien'),
        ),
      ],
    );
  }
}

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({required this.initial});

  final Set<ClientPermission> initial;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late final Set<ClientPermission> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Droits du compte'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in ClientPermission.values)
              CheckboxListTile(
                value: _selected.contains(p),
                title: Text(p.label),
                onChanged: (value) =>
                    setState(() => value == true ? _selected.add(p) : _selected.remove(p)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab({required this.company});

  final ClientCompany company;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final amount = TextEditingController();
    DateTime? due;
    LocalFile? file;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouvelle facture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Objet'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant', suffixText: 'FCFA'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) setState(() => due = picked);
                },
                icon: const Icon(Icons.event),
                label: Text(due == null ? 'Échéance' : 'Échéance : ${formatDate(due!)}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final files = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['pdf'],
                  );
                  final picked = files.firstOrNull;
                  if (picked?.path != null) {
                    setState(() => file = (path: picked!.path!, name: picked.name));
                  }
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(file?.name ?? 'Joindre le PDF'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Émettre'),
            ),
          ],
        ),
      ),
    );
    final value = double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', '.'));
    if (ok != true || title.text.trim().isEmpty || value == null) return;
    try {
      await ref
          .read(clientsRepositoryProvider)
          .createInvoice(
            company.id,
            title: title.text,
            amount: value,
            issueDate: DateTime.now(),
            dueDate: due,
            file: file,
          );
      ref.invalidate(companyInvoicesProvider(company.id));
      if (context.mounted) showMessage(context, 'Facture émise, le client est notifié.');
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(companyInvoicesProvider(company.id));
    final gutter = Breakpoints.gutter(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-invoice',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Facture'),
      ),
      body: AsyncValueView(
        value: invoices,
        onRetry: () => ref.invalidate(companyInvoicesProvider(company.id)),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'Aucune facture.')
            : ResponsiveCenter(
                maxWidth: Breakpoints.readingMaxWidth,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 96),
                  children: [
                    for (final invoice in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          title: Text('${invoice.number} · ${invoice.title}'),
                          subtitle: Text(
                            '${formatMoney(invoice.amount, invoice.currency)} · reste '
                            '${formatMoney(invoice.remainingAmount, invoice.currency)}',
                          ),
                          trailing: Pill(
                            invoice.status == 'cancelled'
                                ? 'Annulée'
                                : paymentStatusLabels[invoice.paymentStatus] ??
                                      invoice.paymentStatus,
                            color: paymentColor(invoice.paymentStatus),
                          ),
                          children: [
                            for (final d in invoice.declarations)
                              ListTile(
                                dense: true,
                                title: Text(
                                  '${formatMoney(d.amount, d.currency)} · ${paymentMethodLabels[d.method] ?? d.method}',
                                ),
                                subtitle: Text(
                                  '${formatDate(d.paidOn)} · ${d.status}'
                                  '${d.rejectionReason != null ? ' · ${d.rejectionReason}' : ''}',
                                ),
                              ),
                            if (invoice.file != null)
                              TextButton.icon(
                                onPressed: () => openClientFile(
                                  context,
                                  ref,
                                  '/clients/invoices/${invoice.id}/download',
                                  invoice.file!.name,
                                ),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('Ouvrir le PDF'),
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

class _ContractsTab extends ConsumerWidget {
  const _ContractsTab({required this.company});

  final ClientCompany company;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final number = TextEditingController();
    final title = TextEditingController();
    final amount = TextEditingController();
    final services = TextEditingController();
    var active = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouveau contrat'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: number,
                  decoration: const InputDecoration(labelText: 'Numéro'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Intitulé'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Montant (facultatif)',
                    suffixText: 'FCFA',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: services,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Prestations'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  title: const Text('Visible du client (actif)'),
                  onChanged: (value) => setState(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true || number.text.trim().isEmpty || title.text.trim().isEmpty) return;
    try {
      final value = double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', '.'));
      await ref.read(clientsRepositoryProvider).createContract(company.id, {
        'number': number.text.trim(),
        'title': title.text.trim(),
        if (value != null) 'amount': value.toStringAsFixed(2),
        if (services.text.trim().isNotEmpty) 'services': services.text.trim(),
        'status': active ? 'active' : 'draft',
      });
      ref.invalidate(companyContractsProvider(company.id));
    } on Exception catch (error) {
      if (context.mounted) showMessage(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contracts = ref.watch(companyContractsProvider(company.id));
    final gutter = Breakpoints.gutter(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-contract',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.handshake_outlined),
        label: const Text('Contrat'),
      ),
      body: AsyncValueView(
        value: contracts,
        onRetry: () => ref.invalidate(companyContractsProvider(company.id)),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.handshake_outlined, message: 'Aucun contrat.')
            : ResponsiveCenter(
                maxWidth: Breakpoints.readingMaxWidth,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 96),
                  children: [
                    for (final contract in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('${contract.number} · ${contract.title}'),
                          subtitle: Text(
                            [
                              if (contract.amount != null)
                                formatMoney(contract.amount!, contract.currency),
                              if (contract.file != null) contract.file!.name else 'Sans document',
                            ].join(' · '),
                          ),
                          trailing: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Pill(contractStatusLabels[contract.status] ?? contract.status),
                              IconButton(
                                tooltip: 'Joindre le PDF',
                                icon: const Icon(Icons.upload_file),
                                onPressed: () async {
                                  final files = await FilePicker.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: const ['pdf'],
                                  );
                                  final picked = files.firstOrNull;
                                  if (picked?.path == null) return;
                                  try {
                                    await ref.read(clientsRepositoryProvider).setContractFile(
                                      contract.id,
                                      (path: picked!.path!, name: picked.name),
                                    );
                                    ref.invalidate(companyContractsProvider(company.id));
                                  } on Exception catch (error) {
                                    if (context.mounted) showMessage(context, error);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
