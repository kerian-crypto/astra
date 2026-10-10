import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/features/auth/presentation/auth_controller.dart';
import 'package:astra_client/features/auth/presentation/auth_layout.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Message d'expiration de session, montré une seule fois.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = ref.read(sessionNoticeProvider);
      if (notice != null && mounted) {
        setState(() => _error = notice);
        ref.read(sessionNoticeProvider.notifier).show(null);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
          .login(email: _email.text, password: _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AuthLayout(
      title: 'Bienvenue',
      subtitle: 'Connectez-vous à votre espace client Astra.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[_ErrorBanner(_error!), const SizedBox(height: Space.lg)],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Adresse email',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) =>
                    (value == null || !value.contains('@')) ? 'Saisissez votre email.' : null,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Afficher' : 'Masquer',
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Saisissez votre mot de passe.' : null,
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
                    : const Text('Se connecter'),
              ),
              const SizedBox(height: Space.xl),
              const Divider(),
              const SizedBox(height: Space.lg),
              Text(
                'Première connexion ou mot de passe oublié ?',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Utilisez le lien d\'activation transmis par votre contact Astra. '
                'Il peut vous en envoyer un nouveau à tout moment.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.md),
              OutlinedButton.icon(
                onPressed: () => context.push(Routes.activate),
                icon: const Icon(Icons.key_rounded),
                label: const Text('J\'ai un lien d\'activation'),
              ),
              const SizedBox(height: Space.sm),
              TextButton.icon(
                onPressed: () => context.go(Routes.register),
                icon: const Icon(Icons.rocket_launch_outlined),
                label: const Text('Nouveau client ? Créer mon espace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: Tone.danger.background(scheme),
        borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: scheme.error, size: 20),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}
