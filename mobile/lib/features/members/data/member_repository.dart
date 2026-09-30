import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/members/data/member.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => MemberRepository(ref.watch(dioProvider)),
);

class MemberRepository {
  MemberRepository(this._dio);

  final Dio _dio;

  /// Annuaire des membres actifs d'Astra.
  Future<List<Member>> list() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/users', queryParameters: {'limit': 100});
    return listOf(response.data, Member.fromJson);
  });
}

final membersProvider = FutureProvider.autoDispose<List<Member>>(
  (ref) => ref.watch(memberRepositoryProvider).list(),
);
