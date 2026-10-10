import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/features/auth/data/auth_repository.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/auth/presentation/auth_layout.dart';

const minPasswordLength = 12;

/// Activation du compte ou nouveau mot de passe, avec le lien d'Astra
/// (ouvert directement depuis le lien, ou collé ici).
class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({this.token, super.key});

  final String? token;

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _link = TextEditingController(text: widget.token ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = tokenFromActivationInput(_link.text);
    if (token == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .activate(token: token, password: _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasToken = widget.token != null && widget.token!.isNotEmpty;
    return AuthLayout(
      title: 'Activer mon accès',
      subtitle: 'Choisissez votre mot de passe pour accéder à votre espace client.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: Space.lg),
            ],
            if (!hasToken) ...[
              TextFormField(
                controller: _link,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Lien ou code d\'activation',
                  helperText: 'Collez le lien reçu de votre contact Astra.',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                validator: (value) => tokenFromActivationInput(value ?? '') == null
                    ? 'Lien d\'activation non reconnu.'
                    : null,
              ),
              const SizedBox(height: Space.lg),
            ],
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: 'Au moins $minPasswordLength caractères.',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) => (value ?? '').length < minPasswordLength
                  ? 'Au moins $minPasswordLength caractères.'
                  : null,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
              validator: (value) =>
                  value != _password.text ? 'Les mots de passe ne correspondent pas.' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Activer et me connecter'),
            ),
          ],
        ),
      ),
    );
  }
}
