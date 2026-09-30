import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/features/auth/data/registration_repository.dart';
import 'package:astra_hub/features/auth/presentation/register_steps.dart';

/// Inscription pas à pas. Le compte est créé en attente : un administrateur
/// le valide et choisit le rôle définitif.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _titles = [
    'Identité',
    'Photo de profil',
    'Poste et rôle',
    'Compétences',
    'Mot de passe',
    'Récapitulatif',
  ];

  final _formKey = GlobalKey<FormState>();
  final _fields = RegistrationFields();
  int _step = 0;
  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;

  bool get _isLastStep => _step == _titles.length - 1;

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  void _next() {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_isLastStep) {
      _submit();
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  void _back() {
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() {
      _error = null;
      _step -= 1;
    });
  }

  Future<void> _pickPhoto() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    final file = files.firstOrNull;
    if (file?.path == null) return;
    setState(() {
      _fields.photoPath = file!.path;
      _fields.photoName = file.name;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final message = await ref.read(registrationRepositoryProvider).register(_fields.toData());
      if (mounted) setState(() => _successMessage = message);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _currentStep() => switch (_step) {
    0 => IdentityStep(fields: _fields),
    1 => PhotoStep(
      fields: _fields,
      onPick: _pickPhoto,
      onRemove: () => setState(() {
        _fields.photoPath = null;
        _fields.photoName = null;
      }),
    ),
    2 => RoleStep(
      fields: _fields,
      onRoleChanged: (level) => setState(() => _fields.requestedAccessLevel = level),
    ),
    3 => SkillsStep(fields: _fields, onChanged: () => setState(() {})),
    4 => PasswordStep(fields: _fields),
    _ => SummaryStep(fields: _fields, onEdit: (step) => setState(() => _step = step)),
  };

  @override
  Widget build(BuildContext context) {
    if (_successMessage != null) return _SuccessView(message: _successMessage!);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer un compte'),
        leading: IconButton(
          tooltip: _step == 0 ? 'Fermer' : 'Étape précédente',
          icon: Icon(_step == 0 ? Icons.close : Icons.arrow_back),
          onPressed: _isSubmitting ? null : _back,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_step + 1) / _titles.length),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Étape ${_step + 1} sur ${_titles.length}', style: textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(_titles[_step], style: textTheme.headlineSmall),
                    const SizedBox(height: 24),
                    // Clé par étape : les champs gardent leur état propre.
                    KeyedSubtree(key: ValueKey(_step), child: _currentStep()),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        key: const Key('register-error'),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : _back,
                        child: const Text('Précédent'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _next,
                      child: _isSubmitting
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isLastStep ? 'Envoyer ma demande' : 'Suivant'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(height: 24),
                Text('Demande envoyée', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                  'Vous pourrez vous connecter dès que votre compte sera validé.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => context.go(Routes.login),
                  child: const Text('Retour à la connexion'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
