import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_http.dart';

void main() {
  group('Member', () {
    test('parses the API payload', () {
      final member = Member.fromJson(memberJson(accessLevel: 'manager'));

      expect(member.fullName, 'Ada Lovelace');
      expect(member.accessLevel, AccessLevel.manager);
      expect(member.skills, ['Flutter', 'FastAPI']);
      expect(member.canCreateProjects, isTrue);
      expect(member.initials, 'AL');
    });

    test('plain members cannot create projects', () {
      expect(Member.fromJson(memberJson()).canCreateProjects, isFalse);
    });

    test('skills list is unmodifiable', () {
      final member = Member.fromJson(memberJson());

      expect(() => member.skills.add('x'), throwsUnsupportedError);
    });

    test('unknown access level falls back to member', () {
      final member = Member.fromJson(memberJson(accessLevel: 'superuser'));

      expect(member.accessLevel, AccessLevel.member);
    });
  });

  group('ProjectDetail', () {
    test('parses project, members and my role', () {
      final detail = ProjectDetail.fromJson({
        ...projectJson(),
        'members': [
          {'user': memberJson(), 'role': 'lead'},
        ],
        'my_role': 'lead',
      });

      expect(detail.project.status, ProjectStatus.active);
      expect(detail.project.priority, Priority.high);
      expect(detail.project.dueDate, DateTime(2026, 12, 31));
      expect(detail.project.budget, '1500.50');
      expect(detail.members.single.role, ProjectRole.lead);
      expect(detail.myRole, ProjectRole.lead);
    });
  });

  group('ApiException.fromDio', () {
    DioException errorWith(int status, Object? data) {
      final options = RequestOptions(path: '/x');
      return DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: status, data: data),
      );
    }

    test('uses the backend detail message', () {
      final error = ApiException.fromDio(errorWith(409, {'detail': 'Déjà pris.'}));

      expect(error.message, 'Déjà pris.');
      expect(error.statusCode, 409);
    });

    test('uses the first validation error message', () {
      final error = ApiException.fromDio(
        errorWith(422, {
          'detail': [
            {'msg': 'Champ requis'},
          ],
        }),
      );

      expect(error.message, 'Champ requis');
    });

    test('maps connectivity problems to a network message', () {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(error.message, contains('Connexion impossible'));
      expect(error.statusCode, isNull);
    });

    test('flags unauthorized responses', () {
      expect(ApiException.fromDio(errorWith(401, null)).isUnauthorized, isTrue);
    });
  });
}
