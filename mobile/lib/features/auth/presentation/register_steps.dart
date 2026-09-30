import 'dart:io';

import 'package:flutter/material.dart';

import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/auth/data/registration_repository.dart';
import 'package:astra_hub/features/members/data/member.dart';

const minPasswordLength = 12;
const maxSkills = 30;

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// État de l'assistant, partagé entre les étapes.
class RegistrationFields {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final jobTitle = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final skillInput = TextEditingController();
  final List<String> skills = [];
  AccessLevel requestedAccessLevel = AccessLevel.member;
  String? photoPath;
  String? photoName;

  String get fullName => '${firstName.text.trim()} ${lastName.text.trim()}';

  /// Ajoute une compétence (sans doublon, casse ignorée) ; vrai si ajoutée.
  bool addSkill(String raw) {
    final skill = raw.trim();
    final exists = skills.any((s) => s.toLowerCase() == skill.toLowerCase());
    if (skill.isEmpty || exists || skills.length >= maxSkills) return false;
    skills.add(skill);
    return true;
  }

  RegistrationData toData() => RegistrationData(
    firstName: firstName.text,
    lastName: lastName.text,
    email: email.text,
    jobTitle: jobTitle.text,
    requestedAccessLevel: requestedAccessLevel,
    skills: List.unmodifiable(skills),
    password: password.text,
    photoPath: photoPath,
    photoName: photoName,
  );

  void dispose() {
    for (final controller in [
      firstName,
      lastName,
      email,
      jobTitle,
      password,
      confirmation,
      skillInput,
    ]) {
      controller.dispose();
    }
  }
}

String? _required(String? value, String message) =>
    (value == null || value.trim().isEmpty) ? message : null;

class IdentityStep extends StatelessWidget {
  const IdentityStep({required this.fields, super.key});

  final RegistrationFields fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: fields.firstName,
          decoration: const InputDecoration(labelText: 'Prénom'),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.givenName],
          maxLength: 60,
          validator: (v) => _required(v, 'Saisissez votre prénom.'),
        ),
        TextFormField(
          controller: fields.lastName,
          decoration: const InputDecoration(labelText: 'Nom'),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.familyName],
          maxLength: 60,
          validator: (v) => _required(v, 'Saisissez votre nom.'),
        ),
        TextFormField(
          controller: fields.email,
          decoration: const InputDecoration(labelText: 'Email professionnel'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: (v) {
            final email = v?.trim() ?? '';
            if (email.isEmpty) return 'Saisissez votre email.';
            return _emailPattern.hasMatch(email) ? null : 'Email invalide.';
          },
        ),
      ],
    );
  }
}

class PhotoStep extends StatelessWidget {
  const PhotoStep({required this.fields, required this.onPick, required this.onRemove, super.key});

  final RegistrationFields fields;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final path = fields.photoPath;
    final initials = [
      fields.firstName.text,
      fields.lastName.text,
    ].where((p) => p.trim().isNotEmpty).map((p) => p.trim()[0].toUpperCase()).join();
    return Column(
      children: [
        CircleAvatar(
          radius: 64,
          backgroundColor: AstraTheme.primary.withValues(alpha: 0.25),
          foregroundImage: path == null ? null : FileImage(File(path)),
          child: Text(initials, style: const TextStyle(fontSize: 40)),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(path == null ? 'Choisir une photo' : 'Changer de photo'),
        ),
        if (path != null) TextButton(onPressed: onRemove, child: const Text('Retirer la photo')),
        const SizedBox(height: 8),
        Text(
          'Facultatif. PNG ou JPEG, 5 Mo maximum. Visible uniquement par les membres d\'Astra.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class RoleStep extends StatelessWidget {
  const RoleStep({required this.fields, required this.onRoleChanged, super.key});

  final RegistrationFields fields;
  final ValueChanged<AccessLevel> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: fields.jobTitle,
          decoration: const InputDecoration(
            labelText: 'Poste',
            hintText: 'Ex. : Développeur Full Stack',
          ),
          textCapitalization: TextCapitalization.sentences,
          maxLength: 120,
          validator: (v) => _required(v, 'Indiquez votre poste.'),
        ),
        const SizedBox(height: 16),
        Text('Rôle souhaité dans ASTRA HUB', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<AccessLevel>(
          segments: const [
            ButtonSegment(
              value: AccessLevel.member,
              icon: Icon(Icons.person_outline),
              label: Text('Membre'),
            ),
            ButtonSegment(
              value: AccessLevel.manager,
              icon: Icon(Icons.supervisor_account_outlined),
              label: Text('Manager'),
            ),
          ],
          selected: {fields.requestedAccessLevel},
          onSelectionChanged: (selection) => onRoleChanged(selection.first),
        ),
        const SizedBox(height: 12),
        Text(
          fields.requestedAccessLevel == AccessLevel.manager
              ? 'Un manager peut créer et piloter des projets.'
              : 'Un membre participe aux projets auxquels il est ajouté.',
        ),
        const SizedBox(height: 8),
        Text(
          'Le rôle définitif est choisi par un administrateur lors de la validation.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class SkillsStep extends StatelessWidget {
  const SkillsStep({required this.fields, required this.onChanged, super.key});

  static const suggestions = [
    'Flutter',
    'FastAPI',
    'PostgreSQL',
    'DevOps',
    'UX/UI',
    'Marketing',
    'Gestion de projet',
    'Communication',
  ];

  final RegistrationFields fields;
  final VoidCallback onChanged;

  void _add(String value) {
    if (fields.addSkill(value)) {
      fields.skillInput.clear();
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = suggestions.where((s) => !fields.skills.contains(s)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: fields.skillInput,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          maxLength: 60,
          decoration: InputDecoration(
            labelText: 'Ajouter une compétence',
            suffixIcon: IconButton(
              tooltip: 'Ajouter la compétence',
              icon: const Icon(Icons.add),
              onPressed: () => _add(fields.skillInput.text),
            ),
          ),
          onSubmitted: _add,
        ),
        if (fields.skills.isEmpty)
          Text(
            'Facultatif, mais utile pour vous proposer les bonnes tâches.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final skill in fields.skills)
              InputChip(
                label: Text(skill),
                onDeleted: () {
                  fields.skills.remove(skill);
                  onChanged();
                },
              ),
          ],
        ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Suggestions', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in available)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(skill),
                  onPressed: () => _add(skill),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class PasswordStep extends StatefulWidget {
  const PasswordStep({required this.fields, super.key});

  final RegistrationFields fields;

  @override
  State<PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<PasswordStep> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final fields = widget.fields;
    final length = fields.password.text.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: fields.password,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Afficher' : 'Masquer',
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) => (v ?? '').length < minPasswordLength
              ? 'Au moins $minPasswordLength caractères.'
              : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              length >= minPasswordLength ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: length >= minPasswordLength ? AstraTheme.accent : AstraTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$minPasswordLength caractères minimum ($length/$minPasswordLength)'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: fields.confirmation,
          obscureText: _obscure,
          decoration: const InputDecoration(labelText: 'Confirmation du mot de passe'),
          validator: (v) =>
              v != fields.password.text ? 'Les mots de passe ne correspondent pas.' : null,
        ),
        const SizedBox(height: 12),
        Text(
          'Astuce : une phrase de plusieurs mots est plus sûre et plus facile à retenir.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class SummaryStep extends StatelessWidget {
  const SummaryStep({required this.fields, required this.onEdit, super.key});

  final RegistrationFields fields;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, String value, int step) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(value),
      subtitle: Text(label),
      trailing: IconButton(
        tooltip: 'Modifier : $label',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => onEdit(step),
      ),
    );

    return Column(
      children: [
        row(Icons.badge_outlined, 'Nom', fields.fullName, 0),
        row(Icons.email_outlined, 'Email', fields.email.text.trim(), 0),
        row(
          Icons.image_outlined,
          'Photo',
          fields.photoPath == null ? 'Aucune' : fields.photoName ?? 'Photo choisie',
          1,
        ),
        row(Icons.work_outline, 'Poste', fields.jobTitle.text.trim(), 2),
        row(Icons.shield_outlined, 'Rôle souhaité', fields.requestedAccessLevel.label, 2),
        row(
          Icons.psychology_outlined,
          'Compétences',
          fields.skills.isEmpty ? 'Aucune' : fields.skills.join(', '),
          3,
        ),
        row(Icons.lock_outline, 'Mot de passe', '•' * 8, 4),
        const SizedBox(height: 8),
        Text(
          'Votre demande sera examinée par un administrateur.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
