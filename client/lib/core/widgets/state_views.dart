import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/theme/client_theme.dart';

/// Message d'état pleine largeur : vide, erreur, hors ligne, accès refusé…
class StateMessage extends StatelessWidget {
  const StateMessage({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = Tone.neutral,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Tone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Space.xl, vertical: compact ? Space.lg : 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 48 : 72,
                height: compact ? 48 : 72,
                decoration: BoxDecoration(
                  color: tone.background(scheme),
                  borderRadius: BorderRadius.circular(compact ? 14 : 22),
                ),
                child: Icon(icon, size: compact ? 24 : 34, color: tone.foreground(scheme)),
              ),
              const SizedBox(height: Space.lg),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: Space.sm),
                Text(
                  message!,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: Space.xl), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Écran d'erreur adapté à sa cause (§54) : hors ligne, interdit, introuvable,
/// session expirée ou erreur serveur.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({required this.error, this.onRetry, this.compact = false, super.key});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final failure = error is ApiException ? error as ApiException : null;
    final retry = onRetry == null
        ? null
        : OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          );
    final (icon, title, message, tone) = switch (failure?.kind) {
      ApiErrorKind.offline => (
        Icons.wifi_off_rounded,
        'Vous êtes hors ligne',
        'Ces informations n\'ont pas encore été enregistrées sur votre téléphone. '
            'Reconnectez-vous à internet pour les afficher.',
        Tone.warning,
      ),
      ApiErrorKind.forbidden => (
        Icons.lock_outline_rounded,
        'Accès non autorisé',
        'Votre compte n\'a pas accès à cette rubrique. '
            'Contactez votre interlocuteur Astra si vous en avez besoin.',
        Tone.neutral,
      ),
      ApiErrorKind.notFound => (
        Icons.search_off_rounded,
        'Élément introuvable',
        'Il a peut-être été retiré ou n\'est plus partagé avec vous.',
        Tone.neutral,
      ),
      ApiErrorKind.unauthorized => (
        Icons.timer_off_outlined,
        'Session expirée',
        'Reconnectez-vous pour continuer.',
        Tone.info,
      ),
      _ => (
        Icons.error_outline_rounded,
        'Un problème est survenu',
        failure?.message ?? 'Réessayez dans quelques instants.',
        Tone.danger,
      ),
    };
    final canRetry =
        failure == null ||
        !{
          ApiErrorKind.forbidden,
          ApiErrorKind.notFound,
          ApiErrorKind.unauthorized,
        }.contains(failure.kind);
    return StateMessage(
      icon: icon,
      title: title,
      message: message,
      tone: tone,
      compact: compact,
      action: canRetry ? retry : null,
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
  );
}

/// Affiche un [AsyncValue] : chargement, erreur typée, vide, ou contenu.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.value,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.empty,
    this.compact = false,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Pendant un rafraîchissement, on garde les données déjà affichées.
    if (value.hasValue) {
      final data = value.requireValue;
      if (empty != null && (isEmpty?.call(data) ?? false)) return empty!;
      return builder(data);
    }
    if (value.hasError) {
      return ErrorStateView(error: value.error!, onRetry: onRetry, compact: compact);
    }
    return compact
        ? const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        : const LoadingView();
  }
}

/// Bandeau discret quand l'écran affiche des données enregistrées hors ligne.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Tone.warning.background(scheme),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
          child: Row(
            children: [
              Icon(Icons.cloud_off_rounded, size: 18, color: Tone.warning.foreground(scheme)),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Hors ligne · dernières données enregistrées. '
                  'Les validations, messages et paiements demandent une connexion.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Tone.warning.foreground(scheme)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Affiche une erreur d'action dans un SnackBar.
void showError(BuildContext context, Object error) {
  final message = switch (error) {
    ApiException(:final message) => message,
    String() => error,
    _ => 'Une erreur est survenue.',
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
