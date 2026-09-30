import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/auth/data/auth_repository.dart';

/// État de session : `null` = non connecté, sinon le membre connecté.
/// En erreur (réseau au démarrage), l'écran d'accueil propose de réessayer.
final authControllerProvider = AsyncNotifierProvider<AuthController, Member?>(AuthController.new);

class AuthController extends AsyncNotifier<Member?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<Member?> build() async {
    final subscription = ref
        .watch(sessionExpiredProvider)
        .stream
        .listen((_) => state = const AsyncData(null));
    ref.onDispose(subscription.cancel);

    if (!await _repository.hasSession()) return null;
    try {
      return await _repository.fetchCurrentMember();
    } on ApiException catch (error) {
      if (!error.isUnauthorized) rethrow;
      await _repository.logout();
      return null;
    }
  }

  /// Lève [ApiException] en cas d'échec ; l'écran de login l'affiche.
  Future<void> login({required String email, required String password}) async {
    await _repository.login(email: email, password: password);
    state = AsyncData(await _repository.fetchCurrentMember());
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AsyncData(null);
  }

  /// Remplace le membre affiché après une modification de profil.
  void updateMember(Member member) => state = AsyncData(member);

  Future<void> retry() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }
}
