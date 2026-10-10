import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/layout/page_frame.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/auth/data/session.dart';
import 'package:astra_client/features/auth/presentation/activation_screen.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/profile/data/profile_repository.dart';

String? _blankToNull(String value) => value.trim().isEmpty ? null : value.trim();

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ClientSession _session = ref.read(sessionProvider)!;
  late final _name = TextEditingController(text: _session.fullName);
  late final _job = TextEditingController(text: _session.jobTitle ?? '');
  late final _phone = TextEditingController(text: _session.phone ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _job.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .updateMe(
            fullName: _name.text.trim(),
            jobTitle: _blankToNull(_job.text),
            phone: _blankToNull(_phone.text),
          );
      ref.read(authControllerProvider.notifier).setSession(updated);
      if (mounted) showSuccess(context, 'Profil mis à jour.');
    } on Exception catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: Form(
        key: _formKey,
        child: FramedListView(
          maxWidth: Breakpoints.formMaxWidth,
          children: [
            Center(child: InitialsAvatar(initials(_session.fullName), radius: 40)),
            const SizedBox(height: Space.md),
            Center(child: Text(_session.email, style: Theme.of(context).textTheme.bodyMedium)),
            const SizedBox(height: Space.xl),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom complet'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Indiquez votre nom.' : null,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _job,
              decoration: const InputDecoration(labelText: 'Fonction'),
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
            const SizedBox(height: Space.xl),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
            const SizedBox(height: Space.lg),
            Text(
              'Pour changer votre adresse email, contactez votre interlocuteur Astra.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fiche de l'entreprise (§37). Le nom et l'email restent gérés par Astra ;
/// les coordonnées sont modifiables par les administrateurs de l'entreprise.
class CompanyScreen extends ConsumerStatefulWidget {
  const CompanyScreen({super.key});

  @override
  ConsumerState<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends ConsumerState<CompanyScreen> {
  late final ClientSession _session = ref.read(sessionProvider)!;
  late final _phone = TextEditingController(text: _session.company.phone ?? '');
  late final _address = TextEditingController(text: _session.company.address ?? '');
  late final _website = TextEditingController(text: _session.company.website ?? '');
  late final _sector = TextEditingController(text: _session.company.sector ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [_phone, _address, _website, _sector]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateCompany(
            phone: _blankToNull(_phone.text),
            address: _blankToNull(_address.text),
            website: _blankToNull(_website.text),
            sector: _blankToNull(_sector.text),
          );
      await ref.read(authControllerProvider.notifier).refresh();
      if (mounted) showSuccess(context, 'Coordonnées mises à jour.');
    } on Exception catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = _session.company;
    final canEdit = _session.can(ClientPermission.manageCompanyUsers);
    InputDecoration field(String label) => InputDecoration(labelText: label);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon entreprise')),
      body: FramedListView(
        maxWidth: Breakpoints.formMaxWidth,
        children: [
          SectionCard(
            child: Row(
              children: [
                InitialsAvatar(company.name.substring(0, 1).toUpperCase(), radius: 28),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company.name, style: Theme.of(context).textTheme.titleLarge),
                      if (company.email != null) Text(company.email!),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xl),
          TextField(controller: _phone, enabled: canEdit, decoration: field('Téléphone')),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _address,
            enabled: canEdit,
            decoration: field('Adresse'),
            maxLines: 2,
          ),
          const SizedBox(height: Space.lg),
          TextField(controller: _website, enabled: canEdit, decoration: field('Site web')),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _sector,
            enabled: canEdit,
            decoration: field('Secteur d\'activité'),
          ),
          const SizedBox(height: Space.xl),
          if (canEdit)
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
          const SizedBox(height: Space.lg),
          Text(
            canEdit ? 'Le nom et l\'email de l\'entreprise sont modifiés par Astra sur demande.' : 'Seuls les administrateurs de votre entreprise peuvent modifier ces informations.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Utilisateurs de l'entreprise (§38), visibles par ses administrateurs.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(companyUsersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      body: AsyncView(
        value: users,
        onRetry: () => ref.invalidate(companyUsersProvider),
        builder: (list) => FramedListView(
          maxWidth: 860,
          children: [
            for (final user in list)
              Card(
                margin: const EdgeInsets.only(bottom: Space.sm),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.xs,
                  ),
                  leading: InitialsAvatar(
                    initials(user.fullName),
                    tone: user.isActive ? Tone.brand : Tone.neutral,
                  ),
                  title: Text(user.fullName),
                  subtitle: Text([?user.jobTitle, user.email].join(' · ')),
                  trailing: !user.isActive
                      ? const StatusPill(label: 'Désactivé')
                      : !user.isActivated
                      ? const StatusPill(label: 'Invitation envoyée', tone: Tone.info)
                      : user.permissions.contains(ClientPermission.manageCompanyUsers)
                      ? const StatusPill(label: 'Administrateur', tone: Tone.brand)
                      : null,
                ),
              ),
            const SizedBox(height: Space.lg),
            Text(
              'Pour ajouter un utilisateur ou modifier ses droits, contactez votre interlocuteur Astra.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .changePassword(current: _current.text, next: _next.text);
      if (!mounted) return;
      showSuccess(context, 'Mot de passe modifié. Reconnectez-vous avec le nouveau.');
      await ref.read(authControllerProvider.notifier).logout();
    } on Exception catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Les données enregistrées sur ce téléphone seront effacées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité')),
      body: Form(
        key: _formKey,
        child: FramedListView(
          maxWidth: Breakpoints.formMaxWidth,
          children: [
            const SectionHeader('Changer de mot de passe'),
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe actuel'),
              validator: (v) => (v ?? '').isEmpty ? 'Saisissez votre mot de passe actuel.' : null,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: 'Au moins $minPasswordLength caractères.',
              ),
              validator: (v) => (v ?? '').length < minPasswordLength
                  ? 'Au moins $minPasswordLength caractères.'
                  : null,
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _saving ? null : _change,
              child: const Text('Modifier le mot de passe'),
            ),
            const SectionHeader('Session'),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}
