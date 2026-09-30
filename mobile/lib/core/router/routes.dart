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
}
