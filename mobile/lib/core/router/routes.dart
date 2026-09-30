abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';

  // Onglets
  static const today = '/today';
  static const projects = '/projects';
  static const messages = '/messages';
  static const meetings = '/meetings';
  static const profile = '/profile';

  // Écrans empilés au-dessus des onglets
  static const notifications = '/notifications';
  static const search = '/search';
  static const ai = '/ai';
  static const health = '/health';
  static const documents = '/documents';
  static const registrations = '/admin/registrations';

  static String project(String id) => '$projects/$id';
  static String chat(String channelId) => '$messages/$channelId';
  static String meeting(String id) => '$meetings/$id';
  static String task(String id) => '/tasks/$id';

  /// Écran d'une entité ciblée par une notification (liste ou push).
  /// `null` : rien à ouvrir (ex. réunion supprimée).
  static String? forEntity(String entityType, String entityId) => switch (entityType) {
    'task' => task(entityId),
    'meeting' => meeting(entityId),
    'channel' => chat(entityId),
    'project' => project(entityId),
    'user' => registrations,
    'ai_conversation' => ai,
    _ => null,
  };
}
