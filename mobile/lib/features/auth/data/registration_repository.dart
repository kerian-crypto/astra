import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/members/data/member.dart';

/// Données saisies dans l'assistant d'inscription.
class RegistrationData {
  const RegistrationData({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.jobTitle,
    required this.requestedAccessLevel,
    required this.skills,
    required this.password,
    this.photoPath,
    this.photoName,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String jobTitle;
  final AccessLevel requestedAccessLevel;
  final List<String> skills;
  final String password;
  final String? photoPath;
  final String? photoName;
}

/// Demande d'inscription vue par un administrateur.
class PendingRegistration {
  const PendingRegistration({required this.member, required this.requestedAccessLevel});

  factory PendingRegistration.fromJson(Json json) => PendingRegistration(
    member: Member.fromJson(json),
    requestedAccessLevel: json['requested_access_level'] == null
        ? AccessLevel.member
        : AccessLevel.fromJson(json['requested_access_level'] as String),
  );

  final Member member;
  final AccessLevel requestedAccessLevel;
}

final registrationRepositoryProvider = Provider<RegistrationRepository>(
  (ref) => RegistrationRepository(ref.watch(dioProvider)),
);

class RegistrationRepository {
  RegistrationRepository(this._dio);

  final Dio _dio;

  /// Envoie la demande ; renvoie le message du serveur.
  Future<String> register(RegistrationData data) => guardApi(() async {
    final form = FormData.fromMap({
      'first_name': data.firstName.trim(),
      'last_name': data.lastName.trim(),
      'email': data.email.trim(),
      'job_title': data.jobTitle.trim(),
      'requested_access_level': data.requestedAccessLevel.name,
      'skills': data.skills,
      'password': data.password,
      if (data.photoPath != null)
        'photo': await MultipartFile.fromFile(
          data.photoPath!,
          filename: data.photoName ?? 'photo.jpg',
        ),
    }, ListFormat.multi);
    final response = await _dio.post<Json>('/auth/register', data: form);
    return response.data?['detail'] as String? ?? 'Demande envoyée.';
  });

  Future<List<PendingRegistration>> pending() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/users/pending');
    return listOf(response.data, PendingRegistration.fromJson);
  });

  Future<void> approve(String userId, AccessLevel level) =>
      guardApi(() => _dio.post<void>('/users/$userId/approve', data: {'access_level': level.name}));

  Future<void> reject(String userId) => guardApi(() => _dio.post<void>('/users/$userId/reject'));

  Future<Member> updateMyPhoto(String path, String filename) => guardApi(() async {
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(path, filename: filename),
    });
    final response = await _dio.put<Json>('/users/me/photo', data: form);
    return Member.fromJson(response.data!);
  });
}

final pendingRegistrationsProvider = FutureProvider.autoDispose<List<PendingRegistration>>(
  (ref) => ref.watch(registrationRepositoryProvider).pending(),
);
