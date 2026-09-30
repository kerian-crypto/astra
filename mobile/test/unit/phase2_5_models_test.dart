import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/utils/json.dart';
import 'package:astra_hub/features/ai/data/ai.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/home/data/work.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';
import 'package:astra_hub/features/knowledge/data/knowledge.dart';
import 'package:astra_hub/features/meetings/data/meeting.dart';
import 'package:astra_hub/features/projects/data/project.dart';
import 'package:astra_hub/features/tasks/data/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_http.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('Task', () {
    test('parses status with its API name', () {
      final task = Task.fromJson(taskJson(status: 'in_progress', dueDate: '2026-09-01'));

      expect(task.status, TaskStatus.inProgress);
      expect(task.status.apiName, 'in_progress');
      expect(task.priority, Priority.high);
      expect(task.isOverdue(DateTime(2026, 9, 2)), isTrue);
      expect(task.isOverdue(DateTime(2026, 9, 1)), isFalse);
    });

    test('done tasks are never overdue', () {
      final task = Task.fromJson(taskJson(status: 'done', dueDate: '2020-01-01'));

      expect(task.isOverdue(DateTime(2026, 9, 2)), isFalse);
    });

    test('detail parses checklist and dependencies', () {
      final detail = TaskDetail.fromJson({
        ...taskJson(),
        'description': 'd',
        'checklist': [
          {'id': 'i', 'label': 'L', 'is_done': true, 'position': 0},
        ],
        'dependencies': [
          {'id': 'x', 'title': 'Backend', 'status': 'done'},
        ],
        'dependents': <Json>[],
      });

      expect(detail.checklist.single.isDone, isTrue);
      expect(detail.dependencies.single.status, TaskStatus.done);
    });

    test('activity describes status changes in French', () {
      final activity = Activity.fromJson({
        'action': 'status_changed',
        'entity_type': 'task',
        'changes': {
          'status': {'from': 'todo', 'to': 'in_progress'},
        },
        'created_at': '2026-09-02T10:00:00Z',
        'actor': memberJson(),
      });

      expect(activity.describe(), 'Ada Lovelace a changé le statut de la tâche → En cours');
    });
  });

  test('project detail exposes permissions helpers', () {
    final detail = ProjectDetail.fromJson({
      ...projectJson(),
      'members': [
        {'user': memberJson(), 'role': 'lead'},
        {'user': memberJson(id: 'u2', fullName: 'Bob'), 'role': 'viewer'},
      ],
      'my_role': 'contributor',
    });

    expect(detail.canContribute, isTrue);
    expect(detail.isLead, isFalse);
    expect(detail.assignableMembers.map((m) => m.id), ['u1']);
  });

  test('dashboard and my work parse the API payloads', () {
    final dashboard = Dashboard.fromJson({
      'me': {
        'open_tasks': 3,
        'today_tasks': 1,
        'overdue_tasks': 2,
        'upcoming_meetings': 1,
        'unread_notifications': 4,
      },
      'astra': {
        'active_projects': 5,
        'open_tasks': 9,
        'overdue_tasks': 2,
        'projects_needing_attention': [
          {'id': 'p1', 'name': 'P', 'reason': 'Retard'},
        ],
      },
    });
    final work = MyWork.fromJson({
      'today': [taskJson()],
      'overdue': <Json>[],
      'priority': <Json>[],
      'upcoming': <Json>[],
      'meetings': [meetingJson()],
    });

    expect(dashboard.unreadNotifications, 4);
    expect(dashboard.projectsNeedingAttention.single.reason, 'Retard');
    expect(work.today.single.title, 'Maquettes');
    expect(work.meetings.single.title, 'Point hebdo');
  });

  test('meeting detail parses decisions and permissions', () {
    final detail = MeetingDetail.fromJson({
      ...meetingJson(),
      'agenda': null,
      'minutes': 'CR',
      'participants': [memberJson()],
      'decisions': [
        {'id': 'd', 'title': 'Go', 'description': null, 'status': 'validated'},
      ],
      'can_edit': false,
    });

    expect(detail.decisions.single.status, DecisionStatus.validated);
    expect(detail.canEdit, isFalse);
    expect(detail.meeting.status, MeetingStatus.planned);
  });

  group('chat', () {
    test('channel titles depend on the kind', () {
      expect(Channel.fromJson(channelJson()).title, '# général');
      expect(
        Channel.fromJson({...channelJson(), 'kind': 'direct', 'display_name': 'Bob'}).title,
        'Bob',
      );
      expect(
        Channel.fromJson({...channelJson(), 'kind': 'project', 'display_name': 'P'}).title,
        'Projet · P',
      );
    });

    test('messages parse reactions', () {
      final message = ChatMessage.fromJson({
        ...messageJson(),
        'reactions': [
          {'emoji': '👍', 'count': 2, 'reacted_by_me': true},
        ],
      });

      expect(message.reactions.single.reactedByMe, isTrue);
      expect(message.author?.fullName, 'Bob Martin');
    });

    test('notification kinds map to enum values', () {
      final n = AppNotification.fromJson({
        'id': 'n',
        'kind': 'mention',
        'title': 't',
        'body': null,
        'entity_type': 'channel',
        'entity_id': 'c1',
        'read_at': null,
        'created_at': '2026-09-02T10:00:00Z',
      });

      expect(n.kind, NotificationKind.mention);
      expect(n.isUnread, isTrue);
    });
  });

  group('knowledge', () {
    test('document size is human readable', () {
      Json doc(int size) => {
        'id': 'd',
        'project_id': null,
        'title': 'T',
        'kind': 'guide',
        'filename': 'a.pdf',
        'size_bytes': size,
        'uploaded_by': null,
        'created_at': '2026-09-02T10:00:00Z',
        'is_indexed': true,
      };

      expect(AstraDocument.fromJson(doc(500)).readableSize, '500 o');
      expect(AstraDocument.fromJson(doc(2048)).readableSize, '2 Ko');
      expect(AstraDocument.fromJson(doc(3 * 1024 * 1024)).readableSize, '3.0 Mo');
      expect(AstraDocument.fromJson(doc(1)).kind, DocumentKind.guide);
    });

    test('health groups indicators into sections', () {
      final health = AstraHealth.fromJson({
        'overdue_tasks': [taskJson()],
        'blocked_tasks': <Json>[],
        'critical_dependencies': [
          {'task': taskJson(title: 'Backend'), 'waiting_tasks': 3},
        ],
        'overloaded_members': <Json>[],
        'unexecuted_decisions': <Json>[],
        'missing_information': <Json>[],
        'projects_at_risk': <Json>[],
      });

      expect(health.isHealthy, isFalse);
      expect(health.sections['Tâches en retard']!.single.taskId, 't1');
      expect(
        health.sections['Dépendances critiques']!.single.subtitle,
        '3 tâches attendent celle-ci',
      );
    });
  });

  group('ai', () {
    test('plan proposal exposes phases and tasks', () {
      final proposal = PlanProposal.fromJson({
        'plan': {
          'name': 'Formations',
          'objective': 'Former',
          'phases': [
            {
              'name': 'Analyse',
              'tasks': [
                {'title': 'Interviews'},
              ],
            },
          ],
        },
        'deliverables': ['CDC'],
        'risks': <String>[],
        'required_skills': ['FastAPI'],
        'estimated_workload_days': 30,
      });

      expect(proposal.name, 'Formations');
      expect(proposal.phases.single.tasks, ['Interviews']);
    });

    test('proposed meeting task converts to a task creation payload', () {
      final task = ProposedTask.fromJson({
        'title': 'API',
        'description': '',
        'assignee_id': 'u1',
        'assignee_name': 'Ada',
        'due_date': null,
      });

      expect(task.toTaskCreate(), {'title': 'API', 'assignee_id': 'u1'});
    });
  });

  group('formatting', () {
    final now = DateTime(2026, 9, 2, 15);

    test('relative days', () {
      expect(relativeDay(DateTime(2026, 9, 2), now: now), 'aujourd\'hui');
      expect(relativeDay(DateTime(2026, 9, 3), now: now), 'demain');
      expect(relativeDay(DateTime(2026, 9, 1), now: now), 'hier');
      expect(relativeDay(DateTime(2026, 9, 7), now: now), 'dans 5 j');
      expect(relativeDay(DateTime(2026, 8, 30), now: now), 'il y a 3 j');
    });

    test('iso dates for the API', () {
      expect(isoDate(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });

    test('short moment shows the time for today only', () {
      expect(formatShortMoment(DateTime(2026, 9, 2, 9, 5), now: now), '09:05');
      expect(formatShortMoment(DateTime(2026, 8, 3), now: now), '3 août');
    });
  });

  group('AiConversation', () {
    test('parses messages, their status and the pending flag', () {
      final conversation = AiConversation.fromJson({
        'id': 'ac1',
        'title': 'Priorités',
        'created_at': '2026-09-02T10:00:00Z',
        'updated_at': '2026-09-02T10:05:00Z',
        'is_pending': true,
        'messages': [
          {
            'id': 'm1',
            'role': 'user',
            'content': 'Priorités ?',
            'sources': <Json>[],
            'status': 'done',
            'created_at': '2026-09-02T10:00:00Z',
          },
          {
            'id': 'm2',
            'role': 'assistant',
            'content': '',
            'sources': [
              {'number': 1, 'type': 'work', 'id': 't1', 'title': 'Maquettes'},
            ],
            'status': 'pending',
            'created_at': '2026-09-02T10:00:01Z',
          },
        ],
      });

      expect(conversation.isPending, isTrue);
      expect(conversation.updatedAt, DateTime.utc(2026, 9, 2, 10, 5));
      expect(conversation.messages.first.isUser, isTrue);
      expect(conversation.messages.last.status, AiMessageStatus.pending);
      expect(conversation.messages.last.sources.single.title, 'Maquettes');
    });

    test('summary parses without messages', () {
      final summary = AiConversationSummary.fromJson({
        'id': 'ac1',
        'title': 'Priorités',
        'updated_at': '2026-09-02T10:05:00Z',
        'is_pending': false,
      });

      expect(summary.isPending, isFalse);
    });
  });

  group('AiFocus', () {
    test('is deduced from detail screens only', () {
      expect(AiFocus.fromPath('/projects/p1')?.query, 'project:p1');
      expect(AiFocus.fromPath('/tasks/t1')?.query, 'task:t1');
      expect(AiFocus.fromPath('/meetings/m1')?.query, 'meeting:m1');
      expect(AiFocus.fromPath('/messages/c1')?.query, 'channel:c1');
      expect(AiFocus.fromPath('/projects'), isNull);
      expect(AiFocus.fromPath('/profile/x'), isNull);
    });

    test('parses the query parameter and rejects malformed values', () {
      final focus = AiFocus.parse('task:t1');

      expect((focus?.type, focus?.id, focus?.label), ('task', 't1', 'Cette tâche'));
      expect(AiFocus.parse(null), isNull);
      expect(AiFocus.parse('task'), isNull);
      expect(AiFocus.parse(':t1'), isNull);
      expect(AiFocus.parse('task:'), isNull);
      expect(const AiFocus('other', 'x').label, 'Cet écran');
    });
  });

  test('AiAction parses a proposal and its result', () {
    final message = AiMessage.fromJson({
      'id': 'm1',
      'role': 'assistant',
      'content': 'Proposition',
      'sources': <Json>[],
      'status': 'done',
      'action': {
        'kind': 'schedule_meeting',
        'status': 'applied',
        'title': 'Planifier la réunion « Revue »',
        'details': ['Date : 05/10/2026 à 14:30'],
        'payload': <String, dynamic>{},
        'result_type': 'meeting',
        'result_id': 'mt1',
      },
    });

    final action = message.action;
    expect(action?.status, AiActionStatus.applied);
    expect(action?.details, ['Date : 05/10/2026 à 14:30']);
    expect((action?.resultType, action?.resultId), ('meeting', 'mt1'));
    expect(message.withAction(action!).action, same(action));
  });

  test('ChatMessage exposes its attachment and a readable preview', () {
    final voice = ChatMessage.fromJson({
      ...messageJson(body: ''),
      'attachment': {
        'kind': 'audio',
        'name': 'vocal.m4a',
        'content_type': 'audio/mp4',
        'size_bytes': 2048,
        'duration_ms': 4200,
      },
    });
    final text = ChatMessage.fromJson(messageJson(body: 'Salut'));

    expect(voice.attachment?.kind, AttachmentKind.audio);
    expect(voice.attachment?.durationMs, 4200);
    expect(voice.preview, '🎤 Message vocal');
    expect(text.attachment, isNull);
    expect(text.preview, 'Salut');
    expect(
      const ChatAttachment(
        kind: AttachmentKind.file,
        name: 'devis.pdf',
        contentType: 'application/pdf',
        sizeBytes: 1,
      ).label,
      '📄 devis.pdf',
    );
  });

  test('photos are only loaded from the API, never from a third-party site', () {
    expect(resolvePhotoUrl('users/u1/photo?v=1'), endsWith('/users/u1/photo?v=1'));
    expect(resolvePhotoUrl('https://attacker.example/x.png'), isNull);
    expect(resolvePhotoUrl('//attacker.example/x.png'), isNull);
  });
}
