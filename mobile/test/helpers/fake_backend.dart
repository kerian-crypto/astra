import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:astra_hub/core/network/api_client.dart';
import 'package:astra_hub/core/network/realtime.dart';
import 'package:astra_hub/core/storage/token_storage.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/main.dart';

import 'fake_http.dart';

/// Temps réel inerte : aucun accès réseau ni minuterie dans les tests.
class SilentRealtime extends RealtimeService {
  SilentRealtime() : super(storage: InMemoryTokenStorage(), refreshSession: () async {});

  @override
  void start() {}
}

Json taskJson({
  String id = 't1',
  String title = 'Maquettes',
  String status = 'todo',
  String? dueDate,
  Json? assignee,
}) => {
  'id': id,
  'project_id': 'p1',
  'phase_id': null,
  'title': title,
  'status': status,
  'priority': 'high',
  'assignee': assignee,
  'due_date': dueDate,
  'completed_at': null,
  'updated_at': '2026-09-02T10:00:00Z',
};

Json channelJson({
  String id = 'c1',
  int unread = 2,
  bool canPost = true,
  String? photoUrl,
  bool canManage = false,
}) => {
  'id': id,
  'kind': 'public',
  'name': 'général',
  'display_name': 'général',
  'description': 'Discussions générales',
  'project_id': null,
  'announcements_only': false,
  'is_archived': false,
  'unread_count': unread,
  'last_message_at': '2026-09-02T10:00:00Z',
  'can_post': canPost,
  'photo_url': photoUrl,
  'can_manage': canManage,
  'members': <Json>[],
};

Json messageJson({String id = 'm1', String body = 'Bonjour à tous'}) => {
  'id': id,
  'channel_id': 'c1',
  'author': memberJson(id: 'u2', fullName: 'Bob Martin'),
  'body': body,
  'reply_to_id': null,
  'mentioned_user_ids': <String>[],
  'created_at': '2026-09-02T10:00:00Z',
  'edited_at': null,
  'is_deleted': false,
  'reactions': <Json>[],
};

Json meetingJson({String id = 'mt1'}) => {
  'id': id,
  'project_id': null,
  'title': 'Point hebdo',
  'scheduled_at': '2099-10-01T09:00:00Z',
  'duration_minutes': 60,
  'location': 'Salle A',
  'status': 'planned',
  'created_by_id': 'u1',
};

/// Faux serveur ASTRA HUB : état en mémoire et routes utilisées par l'app.
class FakeBackend {
  FakeBackend({this.accessLevel = 'manager', List<Json>? projects, this.aiEnabled = true})
    : projects = projects ?? [projectJson()];

  final String accessLevel;
  final List<Json> projects;
  final bool aiEnabled;
  final List<Json> tasks = [taskJson(dueDate: '2026-09-01')];
  final List<Json> messages = [messageJson()];
  final List<Json> decisions = [];
  final List<Json> notifications = [
    {
      'id': 'n1',
      'kind': 'task_assigned',
      'title': 'Lead vous a attribué une tâche',
      'body': 'Maquettes',
      'entity_type': 'task',
      'entity_id': 't1',
      'read_at': null,
      'created_at': '2026-09-02T10:00:00Z',
    },
  ];
  final List<String> calls = [];

  /// Photo du canal c1 et droit de le gérer pour le membre connecté.
  String? channelPhoto;
  bool canManageChannel = false;

  Json _channel({Object? photo = _keep}) {
    if (photo != _keep) channelPhoto = photo as String?;
    return channelJson(photoUrl: channelPhoto, canManage: canManageChannel);
  }

  static const _keep = Object();
  bool failDashboard = false;

  Json _projectDetail(Json project) => {
    ...project,
    'members': [
      {'user': memberJson(accessLevel: accessLevel), 'role': 'lead'},
    ],
    'my_role': 'lead',
  };

  Json _taskDetail(Json task) => {
    ...task,
    'description': 'Écrans principaux',
    'created_by_id': 'u1',
    'created_at': '2026-09-01T10:00:00Z',
    'meeting_id': null,
    'decision_id': null,
    'checklist': [
      {'id': 'i1', 'label': 'Accueil', 'is_done': false, 'position': 0},
    ],
    'dependencies': <Json>[],
    'dependents': <Json>[],
  };

  Json _meetingDetail() => {
    ...meetingJson(),
    'agenda': '1. Budget',
    'minutes': 'On valide FastAPI.',
    'participants': [memberJson()],
    'decisions': decisions,
    'can_edit': true,
  };

  Future<FakeResponse> handle(RequestOptions options) async {
    final path = options.path;
    final method = options.method;
    calls.add('$method $path');
    final body = options.data;
    if (method != 'GET') writes['$method $path'] = body;

    if (method == 'GET' && path.startsWith('/projects/') && path.endsWith('/tasks')) {
      return FakeResponse(200, tasks);
    }
    if (method == 'PATCH' && path == '/tasks/t1') {
      final task = tasks.first;
      task.addAll((body as Json).cast<String, dynamic>());
      return FakeResponse(200, _taskDetail(task));
    }
    if (method == 'POST' && path.startsWith('/channels/') && path.endsWith('/attachments')) {
      final form = body! as FormData;
      final fields = Map.fromEntries(form.fields);
      final file = form.files.single.value;
      final name = file.filename ?? 'fichier';
      final created = messageJson(id: 'm${messages.length + 1}', body: fields['body'] ?? '')
        ..['author'] = memberJson(accessLevel: accessLevel)
        ..['attachment'] = {
          'kind': switch (name.split('.').last) {
            'png' || 'jpg' => 'image',
            'mp4' => 'video',
            'm4a' => 'audio',
            _ => 'file',
          },
          'name': name,
          'content_type': 'application/octet-stream',
          'size_bytes': file.length,
          'duration_ms': switch (fields['duration_ms']) {
            final String ms => int.parse(ms),
            _ => null,
          },
        };
      messages.insert(0, created);
      return FakeResponse(201, created);
    }
    if (method == 'POST' && path.startsWith('/channels/') && path.endsWith('/messages')) {
      final created = messageJson(
        id: 'm${messages.length + 1}',
        body: (body as Json)['body'] as String,
      );
      created['author'] = memberJson(accessLevel: accessLevel);
      messages.insert(0, created);
      return FakeResponse(201, created);
    }
    if (method == 'POST' && path.startsWith('/decisions/') && path.endsWith('/review')) {
      decisions.first['status'] = (body as Json)['status'];
      return FakeResponse(200, decisions.first);
    }
    if (method == 'POST' && path.startsWith('/notifications/')) {
      for (final n in notifications) {
        n['read_at'] = '2026-09-02T11:00:00Z';
      }
      return const FakeResponse(200, {});
    }
    final extra = _phase5(method, path, body) ?? _aiConversations(method, path, body);
    if (extra != null) return extra;

    return switch ((method, path)) {
      ('POST', '/auth/login') => const FakeResponse(200, {
        'access_token': 'a',
        'refresh_token': 'r',
      }),
      ('POST', '/auth/logout') => const FakeResponse(204),
      ('GET', '/users/me') => FakeResponse(200, memberJson(accessLevel: accessLevel)),
      ('GET', '/users') => FakeResponse(200, [
        memberJson(accessLevel: accessLevel),
        memberJson(id: 'u2', fullName: 'Bob Martin'),
      ]),
      ('GET', '/dashboard') =>
        failDashboard
            ? const FakeResponse(500, {'detail': 'Serveur indisponible.'})
            : FakeResponse(200, {
                'me': {
                  'open_tasks': 1,
                  'today_tasks': 1,
                  'overdue_tasks': 1,
                  'upcoming_meetings': 0,
                  'unread_notifications': 1,
                },
                'astra': {
                  'active_projects': projects.length,
                  'open_tasks': tasks.length,
                  'overdue_tasks': 1,
                  'projects_needing_attention': [
                    {
                      'id': 'p1',
                      'name': 'MarketCM V2',
                      'status': 'active',
                      'due_date': null,
                      'overdue_tasks': 1,
                      'reason': '1 tâche(s) en retard',
                    },
                  ],
                },
              }),
      ('GET', '/me/work') => FakeResponse(200, {
        'today': <Json>[],
        'overdue': tasks,
        'priority': <Json>[],
        'upcoming': <Json>[],
        'meetings': [meetingJson()],
      }),
      ('GET', '/projects') => FakeResponse(200, projects),
      ('POST', '/projects') => _createProject(body as Json),
      ('GET', '/channels') => FakeResponse(200, [_channel()]),
      ('GET', '/channels/c1') => FakeResponse(200, _channel()),
      ('PUT', '/channels/c1/photo') => FakeResponse(200, _channel(photo: 'channels/c1/photo?v=1')),
      ('DELETE', '/channels/c1/photo') => FakeResponse(200, _channel(photo: null)),
      ('GET', '/channels/c1/messages') => FakeResponse(200, messages),
      ('POST', '/channels/c1/read') => const FakeResponse(204),
      ('GET', '/notifications') => FakeResponse(200, notifications),
      ('GET', '/meetings') => FakeResponse(200, [meetingJson()]),
      ('GET', '/meetings/mt1') => FakeResponse(200, _meetingDetail()),
      ('GET', '/search') => const FakeResponse(200, [
        {
          'type': 'task',
          'id': 't1',
          'title': 'Maquettes',
          'snippet': 'Écrans de «maquettes»',
          'project_id': 'p1',
          'parent_id': null,
          'score': 0.5,
        },
      ]),
      ('GET', '/ai/status') => FakeResponse(200, {
        'enabled': aiEnabled,
        'reachable': aiEnabled,
        'model': aiEnabled ? 'ronda' : null,
      }),
      ('GET', '/tasks/t1') => FakeResponse(200, _taskDetail(tasks.first)),
      ('GET', '/tasks/t1/comments') => const FakeResponse(200, <Json>[]),
      ('GET', '/tasks/t1/history') => const FakeResponse(200, <Json>[]),
      ('GET', _) when path.startsWith('/projects/') && path.endsWith('/phases') =>
        const FakeResponse(200, <Json>[]),
      ('GET', _) when path.startsWith('/projects/') && path.endsWith('/activity') =>
        const FakeResponse(200, <Json>[]),
      ('GET', _) when path.startsWith('/projects/') && path.endsWith('/documents') =>
        const FakeResponse(200, <Json>[]),
      ('GET', _) when path.startsWith('/projects/') => FakeResponse(
        200,
        _projectDetail(projects.firstWhere((p) => '/projects/${p['id']}' == path)),
      ),
      _ => const FakeResponse(404, {'detail': 'Introuvable'}),
    };
  }

  /// Écritures enregistrées (corps des requêtes), pour les assertions.
  final Map<String, Object?> writes = {};

  static const _summary = {
    'summary': 'Choix de FastAPI.',
    'decisions': [
      {'title': 'Adopter FastAPI', 'description': 'Backend'},
    ],
    'open_questions': ['Hébergement ?'],
    'tasks': [
      {
        'title': 'Écrire l\'API',
        'description': '',
        'assignee_id': 'u1',
        'assignee_name': 'Ada Lovelace',
        'due_date': '2026-10-15',
      },
    ],
    'risks': ['Délais'],
  };

  static const _plan = {
    'plan': {
      'name': 'Plateforme de formations',
      'objective': 'Former les membres',
      'phases': [
        {
          'name': 'Analyse',
          'tasks': [
            {'title': 'Interviews', 'priority': 'high'},
          ],
        },
      ],
    },
    'deliverables': ['Cahier des charges'],
    'risks': ['Adoption'],
    'required_skills': ['FastAPI'],
    'estimated_workload_days': 40,
  };

  static const _health = {
    'overdue_tasks': <Json>[],
    'blocked_tasks': <Json>[],
    'critical_dependencies': <Json>[],
    'overloaded_members': <Json>[],
    'unexecuted_decisions': [
      {'id': 'd9', 'title': 'Migrer la base', 'project_id': 'p1', 'validated_on': '2026-09-01'},
    ],
    'missing_information': <Json>[],
    'projects_at_risk': <Json>[],
  };

  static Json _document(String? projectId) => {
    'id': 'doc1',
    'project_id': projectId,
    'title': 'Cahier des charges',
    'kind': 'specification',
    'filename': 'cdc.pdf',
    'size_bytes': 2048,
    'uploaded_by': memberJson(),
    'created_at': '2026-09-01T10:00:00Z',
    'is_indexed': true,
  };

  /// Demandes d'inscription en attente (vue administrateur).
  final List<Json> pendingRegistrations = [
    {
      ...memberJson(id: 'u9', fullName: 'Awa Diallo'),
      'job_title': 'Designer UX',
      'is_active': false,
      'requested_access_level': 'manager',
    },
  ];
  bool pendingLogin = false;

  FakeResponse? _phase5(String method, String path, Object? body) {
    if (method == 'POST' && path == '/auth/login' && pendingLogin) {
      return const FakeResponse(403, {
        'detail': 'Votre compte est en attente de validation par un administrateur.',
      });
    }
    if (method == 'POST' && path.startsWith('/users/u9/')) {
      pendingRegistrations.clear();
      return path.endsWith('/approve')
          ? FakeResponse(200, memberJson(id: 'u9'))
          : const FakeResponse(204);
    }
    return switch ((method, path)) {
      ('POST', '/auth/register') => const FakeResponse(202, {
        'detail': 'Demande envoyée. Un administrateur doit valider votre compte.',
      }),
      ('GET', '/users/pending') => FakeResponse(200, pendingRegistrations),
      ('POST', '/projects/p1/tasks') => FakeResponse(
        201,
        _taskDetail(taskJson(id: 't1', title: (body! as Json)['title'] as String)),
      ),
      ('GET', '/tasks/t1/assignment-suggestions') => FakeResponse(200, [
        {
          'member': memberJson(),
          'score': 5.0,
          'reasons': ['Compétences utiles : Flutter'],
        },
      ]),
      ('POST', '/tasks/t1/comments') => const FakeResponse(201, {}),
      ('POST', '/tasks/t1/checklist') => const FakeResponse(201, {}),
      ('PATCH', '/tasks/t1/checklist/i1') => const FakeResponse(200, {}),
      ('POST', '/meetings') => FakeResponse(201, _meetingDetail()),
      ('POST', '/meetings/mt1/decisions') => FakeResponse(201, {
        'id': 'd2',
        'title': (body! as Json)['title'],
        'status': 'proposed',
      }),
      ('POST', '/meetings/mt1/tasks') => const FakeResponse(201, <Json>[]),
      ('PATCH', '/meetings/mt1') => FakeResponse(200, _meetingDetail()),
      ('POST', '/ai/meetings/mt1/summary') => const FakeResponse(200, _summary),
      ('POST', '/decisions/d1/project') => FakeResponse(201, _projectDetail(projects.first)),
      ('POST', '/ai/plan') => const FakeResponse(200, _plan),
      ('POST', '/projects/from-plan') => FakeResponse(201, _projectDetail(projects.first)),
      ('GET', '/insights/health') => const FakeResponse(200, _health),
      ('GET', '/ai/health-report') => const FakeResponse(200, {'report': '- Décision à exécuter.'}),
      ('GET', '/documents') => FakeResponse(200, [_document(null)]),
      ('GET', '/projects/p1/documents') => FakeResponse(200, [_document('p1')]),
      ('POST', '/channels/direct') => FakeResponse(200, channelJson()),
      ('PUT', _) when path.startsWith('/messages/') => FakeResponse(200, {
        ...messageJson(),
        'reactions': [
          {'emoji': '👍', 'count': 1, 'reacted_by_me': true},
        ],
      }),
      _ => null,
    };
  }

  /// Conversations ASTRA AI : Ronda « termine » sa réponse à la relecture
  /// suivante (GET), comme la génération en arrière-plan du serveur.
  final List<Json> aiConversations = [];

  static const aiAnswer = 'Votre priorité : les maquettes [1].';

  /// Action proposée par Ronda quand la question commence par « Crée ».
  static const _projectAction = {
    'kind': 'create_project',
    'status': 'proposed',
    'title': 'Créer le projet « Livreurs »',
    'details': ['Priorité : high'],
    'payload': {'name': 'Livreurs'},
    'result_type': null,
    'result_id': null,
  };

  Json _aiMessage(String role, String content, String status) => {
    'id': 'am${DateTime.now().microsecondsSinceEpoch}',
    'role': role,
    'content': content,
    'sources': <Json>[],
    'status': status,
    'created_at': '2026-09-02T10:00:00Z',
  };

  Json _withSummary(Json conversation) {
    final messages = (conversation['messages'] as List<dynamic>).cast<Json>();
    return {...conversation, 'is_pending': messages.any((m) => m['status'] == 'pending')};
  }

  FakeResponse? _aiConversations(String method, String path, Object? body) {
    if (!path.startsWith('/ai/conversations')) return null;
    final segments = path.split('/');
    if (method == 'POST' && path.endsWith('/action')) {
      final apply = (body! as Map<dynamic, dynamic>)['apply'] as bool;
      return FakeResponse(200, {
        ..._aiMessage('assistant', aiAnswer, 'done'),
        'id': segments[5],
        'action': {
          ..._projectAction,
          'status': apply ? 'applied' : 'dismissed',
          'result_type': apply ? 'project' : null,
          'result_id': apply ? 'p1' : null,
        },
      });
    }
    final id = segments.length > 3 ? segments[3] : null;
    final conversation = aiConversations.where((c) => c['id'] == id).firstOrNull;
    if (id != null && conversation == null) {
      return const FakeResponse(404, {'detail': 'Conversation introuvable.'});
    }
    if (method == 'GET' && id == null) {
      return FakeResponse(200, [
        for (final c in aiConversations.reversed) {..._withSummary(c)}..remove('messages'),
      ]);
    }
    if (method == 'DELETE') {
      aiConversations.remove(conversation);
      return const FakeResponse(204);
    }
    if (method == 'GET') {
      for (final message in (conversation!['messages'] as List<dynamic>).cast<Json>()) {
        if (message['status'] == 'pending') {
          final asked = (conversation['messages'] as List<dynamic>).cast<Json>();
          final question = asked[asked.indexOf(message) - 1]['content'] as String;
          if (question.startsWith('Crée')) message['action'] = _projectAction;
          message
            ..['status'] = 'done'
            ..['content'] = aiAnswer
            ..['sources'] = [
              {'number': 1, 'type': 'work', 'id': 't1', 'title': 'Maquettes'},
            ];
        }
      }
      return FakeResponse(200, _withSummary(conversation));
    }
    final question = (body! as Map<dynamic, dynamic>)['question'] as String;
    final target =
        conversation ??
        {
          'id': 'ac${aiConversations.length + 1}',
          'title': question,
          'created_at': '2026-09-02T10:00:00Z',
          'updated_at': '2026-09-02T10:00:00Z',
          'messages': <Json>[],
        };
    if (conversation == null) aiConversations.add(target);
    final focus = (body as Map<dynamic, dynamic>)['focus'] as Map<dynamic, dynamic>?;
    (target['messages'] as List<Json>).addAll([
      {..._aiMessage('user', question, 'done'), 'focus_title': ?focus?['type']},
      _aiMessage('assistant', '', 'pending'),
    ]);
    return FakeResponse(201, _withSummary(target));
  }

  FakeResponse _createProject(Json body) {
    final created = {
      ...projectJson(id: 'p-new', status: 'idea'),
      'name': body['name'],
      'objective': body['objective'],
    };
    projects.add(created);
    return FakeResponse(201, _projectDetail(created));
  }

  Widget app({AuthTokens? storedTokens, List<Override> overrides = const []}) => ProviderScope(
    overrides: [
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage(storedTokens)),
      dioProvider.overrideWithValue(fakeDio(FakeHttpAdapter(handle))),
      realtimeServiceProvider.overrideWithValue(SilentRealtime()),
      ...overrides,
    ],
    child: const AstraApp(),
  );
}
