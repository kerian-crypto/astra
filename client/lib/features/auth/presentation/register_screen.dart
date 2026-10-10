import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/features/auth/presentation/activation_screen.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/auth/presentation/auth_layout.dart';

/// Inscription d'un nouveau client : crée son entreprise, puis ouvre le
/// questionnaire de cadrage de son projet.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_company, _name, _email, _phone, _country, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            companyName: _company.text,
            fullName: _name.text,
            email: _email.text,
            password: _password.text,
            phone: _phone.text,
            country: _country.text,
          );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _required(String? value, String message) => (value ?? '').trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const gap = SizedBox(height: Space.lg);
    return AuthLayout(
      title: 'Créer mon espace',
      subtitle: 'Quelques informations, puis décrivez-nous votre projet.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[Text(_error!, style: TextStyle(color: scheme.error)), gap],
            TextFormField(
              controller: _company,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de votre entreprise',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              validator: (v) => _required(v, 'Indiquez le nom de votre entreprise.'),
            ),
            gap,
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Votre nom complet',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => _required(v, 'Indiquez votre nom.'),
            ),
            gap,
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Adresse email',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              validator: (v) => (v ?? '').contains('@') ? null : 'Saisissez un email valide.',
            ),
            gap,
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                labelText: 'Téléphone (WhatsApp)',
                hintText: '+237 6 90 00 00 00',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            gap,
            TextFormField(
              controller: _country,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Pays',
                prefixIcon: Icon(Icons.public_rounded),
              ),
            ),
            gap,
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                helperText: 'Au moins $minPasswordLength caractères.',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v ?? '').length < minPasswordLength
                  ? 'Au moins $minPasswordLength caractères.'
                  : null,
            ),
            gap,
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
              validator: (v) =>
                  v != _password.text ? 'Les mots de passe ne correspondent pas.' : null,
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
                  : const Text('Créer mon espace'),
            ),
            const SizedBox(height: Space.lg),
            TextButton(
              onPressed: () => context.go(Routes.login),
              child: const Text('J\'ai déjà un compte · Se connecter'),
            ),
          ],
        ),
      ),
    );
  }
}
