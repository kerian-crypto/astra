import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_client/core/network/api_client.dart';
import 'package:astra_client/core/utils/json.dart';
import 'package:astra_client/features/auth/data/session.dart';

class CompanyUser {
  const CompanyUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.permissions,
    required this.isActive,
    required this.isActivated,
    this.jobTitle,
  });

  factory CompanyUser.fromJson(Json json) => CompanyUser(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    jobTitle: json['job_title'] as String?,
    email: json['email'] as String,
    permissions: stringsOf(json['permissions']).map(ClientPermission.parse).nonNulls.toSet(),
    isActive: json['is_active'] as bool? ?? true,
    isActivated: json['is_activated'] as bool? ?? false,
  );

  final String id;
  final String fullName;
  final String? jobTitle;
  final String email;
  final Set<ClientPermission> permissions;
  final bool isActive;
  final bool isActivated;
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiProvider)),
);

class ProfileRepository {
  ProfileRepository(this._api);

  final Api _api;

  Future<ClientSession> updateMe({String? fullName, String? jobTitle, String? phone}) => _api.patch(
    '/client/me',
    data: {'full_name': ?fullName, 'job_title': jobTitle, 'phone': phone},
    parse: (data) => ClientSession.fromJson(data! as Json),
  );

  Future<Company> updateCompany({
    String? phone,
    String? address,
    String? website,
    String? sector,
  }) => _api.patch(
    '/client/company',
    data: {'phone': phone, 'address': address, 'website': website, 'sector': sector},
    parse: (data) => Company.fromJson(data! as Json),
  );

  Future<void> changePassword({required String current, required String next}) => _api.post<void>(
    '/client/auth/password',
    data: {'current_password': current, 'new_password': next},
  );

  /// Suppression définitive du compte connecté ; le mot de passe est redemandé.
  Future<void> deleteAccount({required String password}) =>
      _api.delete('/client/me', data: {'password': password});

  Future<List<CompanyUser>> companyUsers() =>
      _api.get('/client/company/users', parse: (data) => listOf(data, CompanyUser.fromJson));
}

final companyUsersProvider = FutureProvider.autoDispose<List<CompanyUser>>(
  (ref) => ref.watch(profileRepositoryProvider).companyUsers(),
);
