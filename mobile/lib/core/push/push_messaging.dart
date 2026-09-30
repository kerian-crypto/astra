import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Données d'un push ouvert par le membre (type, entity_type, entity_id…).
typedef PushData = Map<String, Object?>;

/// Ce dont l'app a besoin de Firebase Cloud Messaging. L'interface permet de
/// tester sans Firebase et de fonctionner quand il n'est pas configuré.
abstract interface class PushMessaging {
  /// `false` si le membre refuse les notifications.
  Future<bool> requestPermission();

  Future<String?> getToken();

  Stream<String> get onTokenRefresh;

  /// Invalide le jeton de l'appareil auprès de Firebase.
  Future<void> deleteToken();

  /// Push qui a lancé l'application (app fermée), une seule fois.
  Future<PushData?> initialMessage();

  /// Push touchés pendant que l'app tourne en arrière-plan.
  Stream<PushData> get onMessageOpened;
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  /// Initialise Firebase ; `null` si l'app n'est pas configurée
  /// (google-services.json absent) : l'app fonctionne alors sans push.
  static Future<FirebasePushMessaging?> initialize() async {
    try {
      await Firebase.initializeApp();
      return FirebasePushMessaging(FirebaseMessaging.instance);
    } on Object catch (error) {
      debugPrint('Notifications push indisponibles : $error');
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<PushData?> initialMessage() async => (await _messaging.getInitialMessage())?.data;

  @override
  Stream<PushData> get onMessageOpened =>
      FirebaseMessaging.onMessageOpenedApp.map((message) => message.data);
}
