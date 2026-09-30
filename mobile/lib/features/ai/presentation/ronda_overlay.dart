import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/router/app_router.dart';
import 'package:astra_hub/core/theme/astra_theme.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';

/// Bouton Ronda présent sur tous les écrans de l'app connectée. Il ouvre
/// l'assistant en lui transmettant l'écran consulté (projet, tâche, réunion,
/// conversation), que Ronda lit avec les droits du membre.
class RondaOverlay extends ConsumerStatefulWidget {
  const RondaOverlay({required this.child, super.key});

  static const buttonKey = Key('ronda-button');

  final Widget child;

  @override
  ConsumerState<RondaOverlay> createState() => _RondaOverlayState();
}

class _RondaOverlayState extends ConsumerState<RondaOverlay> {
  static const _hiddenOn = {Routes.splash, Routes.login, Routes.register, Routes.ai};

  late final GoRouter _router = ref.read(routerProvider);
  String _path = '';

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_onRouteChanged);
    _onRouteChanged();
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    // Le routeur notifie parfois en pleine construction : mise à jour différée.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // `state` suit la route du dessus, y compris celles ouvertes par push().
      final path = _router.state.uri.path;
      if (path != _path && mounted) setState(() => _path = path);
    });
  }

  void _open() {
    final focus = AiFocus.fromPath(_path);
    unawaited(_router.push(focus == null ? Routes.ai : '${Routes.ai}?focus=${focus.query}'));
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = ref.watch(authControllerProvider.select((s) => s.value != null));
    final media = MediaQuery.of(context);
    // Masqué pendant la saisie : il couvrirait le champ de texte.
    final isVisible = isLoggedIn && !_hiddenOn.contains(_path) && media.viewInsets.bottom == 0;
    return Stack(
      children: [
        widget.child,
        if (isVisible)
          Positioned(
            right: 12,
            bottom: media.padding.bottom + 150,
            child: Semantics(
              button: true,
              label: 'Demander à Ronda',
              child: Material(
                key: RondaOverlay.buttonKey,
                color: AstraTheme.primary,
                shape: const CircleBorder(),
                elevation: 6,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _open,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.auto_awesome, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
