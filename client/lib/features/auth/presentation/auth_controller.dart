import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/network/api_exception.dart';
import 'package:astra_client/core/push/push_service.dart';
import 'package:astra_client/features/auth/data/auth_repository.dart';
import 'package:astra_client/features/auth/data/session.dart';

/// Raison du dernier retour à l'écran de connexion (affichée une fois).
final sessionNoticeProvider = NotifierProvider<SessionNotice, String?>(SessionNotice.new);

class SessionNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String? message) => state = message;
}

/// Vrai juste après une inscription : la coque ouvre alors le questionnaire.
final onboardingRequestedProvider = NotifierProvider<OnboardingRequest, bool>(
  OnboardingRequest.new,
);

class OnboardingRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// État de session : `null` = non connecté, sinon le compte client.
final authControllerProvider = AsyncNotifierProvider<AuthController, ClientSession?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<ClientSession?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<ClientSession?> build() async {
    final subscription = ref.watch(sessionExpiredProvider).stream.listen((_) {
      unawaited(ref.read(pushServiceProvider).forgetDevice());
      ref.read(sessionNoticeProvider.notifier).show('Votre session a expiré. Reconnectez-vous.');
      state = const AsyncData(null);
    });
    ref.onDispose(subscription.cancel);

    if (!await _repository.hasSession()) return null;
    try {
      return await _repository.fetchSession();
    } on ApiException catch (error) {
      if (error.isOffline) {
        // Hors ligne au démarrage : on affiche les données enregistrées.
        final cached = await _repository.cachedSession();
        if (cached != null) {
          ref.read(offlineProvider.notifier).set(true);
          return cached;
        }
      }
      if (!error.isUnauthorized) rethrow;
      await _repository.logout();
      return null;
    }
  }

  Future<void> login({required String email, required String password}) async {
    await _repository.login(email: email, password: password);
    state = AsyncData(await _repository.fetchSession());
  }

  Future<void> activate({required String token, required String password}) async {
    await _repository.activate(token: token, password: password);
    state = AsyncData(await _repository.fetchSession());
  }

  Future<void> register({
    required String companyName,
    required String fullName,
    required String email,
    required String password,
    String? phone,
    String? country,
  }) async {
    await _repository.register(
      companyName: companyName,
      fullName: fullName,
      email: email,
      password: password,
      phone: phone,
      country: country,
    );
    ref.read(onboardingRequestedProvider.notifier).set(true);
    state = AsyncData(await _repository.fetchSession());
  }

  Future<void> logout() async {
    await ref.read(pushServiceProvider).unregister();
    await _repository.logout();
    state = const AsyncData(null);
  }

  void setSession(ClientSession session) => state = AsyncData(session);

  Future<void> refresh() async {
    try {
      state = AsyncData(await _repository.fetchSession());
    } on ApiException {
      // Garde la session affichée ; l'écran concerné montrera l'erreur.
    }
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }
}

/// Session courante (non nulle dans les écrans connectés).
final sessionProvider = Provider<ClientSession?>((ref) => ref.watch(authControllerProvider).value);
