import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/projects/data/project.dart';

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(dioProvider)));

class AiRepository {
  AiRepository(this._dio);

  /// Ronda tourne en local sur CPU : une réponse peut prendre plusieurs minutes.
  static const _aiTimeout = Duration(minutes: 11);

  final Dio _dio;

  Options get _slow => Options(receiveTimeout: _aiTimeout);

  Future<Json> _post(String path, Object? data, {Map<String, dynamic>? query}) =>
      guardApi(() async {
        final response = await _dio.post<Json>(
          path,
          data: data,
          queryParameters: query,
          options: _slow,
        );
        return response.data!;
      });

  Future<AiStatus> status() => guardApi(() async {
    final response = await _dio.get<Json>('/ai/status');
    return AiStatus.fromJson(response.data!);
  });

  Future<AiAnswer> ask(String question, List<({String role, String content})> history) async =>
      AiAnswer.fromJson(
        await _post(
          '/ai/ask',
          {
            'question': question.trim(),
            'history': [
              for (final turn in history) {'role': turn.role, 'content': turn.content},
            ],
          },
          query: {'today': isoDate(DateTime.now())},
        ),
      );

  // ---------- Historique des conversations ----------
  // La réponse de Ronda est générée côté serveur : ces appels reviennent tout
  // de suite, avec un dernier message `pending` à relire jusqu'à la fin.

  Future<List<AiConversationSummary>> conversations() => guardApi(() async {
    final response = await _dio.get<List<dynamic>>('/ai/conversations');
    return listOf(response.data, AiConversationSummary.fromJson);
  });

  Future<AiConversation> conversation(String id) => guardApi(() async {
    final response = await _dio.get<Json>('/ai/conversations/$id');
    return AiConversation.fromJson(response.data!);
  });

  /// Pose [question] dans la conversation [conversationId], ou en démarre une
  /// nouvelle si elle est nulle.
  /// [focus] : écran consulté, que Ronda lit en plus de l'activité générale.
  Future<AiConversation> sendQuestion(String question, {String? conversationId, AiFocus? focus}) =>
      guardApi(() async {
        final response = await _dio.post<Json>(
          conversationId == null
              ? '/ai/conversations'
              : '/ai/conversations/$conversationId/messages',
          data: {
            'question': question.trim(),
            'focus': ?focus?.toJson(),
            'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
          },
          queryParameters: {'today': isoDate(DateTime.now())},
        );
        return AiConversation.fromJson(response.data!);
      });

  /// Valide ([apply]) ou écarte l'action proposée par Ronda dans [messageId].
  Future<AiMessage> decideAction(String conversationId, String messageId, {required bool apply}) =>
      guardApi(() async {
        final response = await _dio.post<Json>(
          '/ai/conversations/$conversationId/messages/$messageId/action',
          data: {'apply': apply},
        );
        return AiMessage.fromJson(response.data!);
      });

  Future<void> deleteConversation(String id) =>
      guardApi(() => _dio.delete<void>('/ai/conversations/$id'));

  Future<PlanProposal> proposePlan(String idea) async =>
      PlanProposal.fromJson(await _post('/ai/plan', {'idea': idea.trim()}));

  /// Validation humaine du plan : crée réellement le projet.
  Future<ProjectDetail> applyPlan(Map<String, dynamic> plan) => guardApi(() async {
    final response = await _dio.post<Json>('/projects/from-plan', data: plan);
    return ProjectDetail.fromJson(response.data!);
  });

  Future<MeetingSummary> summarizeMeeting(String meetingId) async => MeetingSummary.fromJson(
    await _post('/ai/meetings/$meetingId/summary', null, query: {'today': isoDate(DateTime.now())}),
  );

  Future<String> healthReport() => guardApi(() async {
    final response = await _dio.get<Json>(
      '/ai/health-report',
      queryParameters: {'today': isoDate(DateTime.now())},
      options: _slow,
    );
    return response.data!['report'] as String;
  });
}

final aiStatusProvider = FutureProvider.autoDispose<AiStatus>(
  (ref) => ref.watch(aiRepositoryProvider).status(),
);

final aiConversationsProvider = FutureProvider.autoDispose<List<AiConversationSummary>>(
  (ref) => ref.watch(aiRepositoryProvider).conversations(),
);

/// Conversation ouverte dans l'assistant : conservée quand on quitte l'écran,
/// pour y revenir (et y voir arriver la réponse de Ronda).
final currentAiConversationProvider = NotifierProvider<CurrentAiConversation, String?>(
  CurrentAiConversation.new,
);

class CurrentAiConversation extends Notifier<String?> {
  @override
  String? build() {
    // Repart de zéro à chaque changement de compte : l'historique est personnel.
    ref.watch(authControllerProvider.select((session) => session.value?.id));
    return null;
  }

  void open(String? conversationId) => state = conversationId;
}
