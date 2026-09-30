# Notifications push (Firebase Cloud Messaging)

Le push est **optionnel** : sans configuration Firebase, l'API et l'application
fonctionnent normalement (notifications visibles dans l'app uniquement).

## Ce qui déclenche un push

| Action | Destinataires | Type |
|---|---|---|
| Message dans un canal ou une conversation | Tous ceux qui y ont accès, sauf l'auteur | `message` |
| Mention `@membre` | Membre mentionné | `mention` |
| Ajout à un projet (création, plan IA, ajout manuel) | Membres ajoutés | `project_added` |
| Changement de statut d'un projet | Membres du projet | `project_status` |
| Attribution d'une tâche | Assigné | `task_assigned` |
| Changement de statut d'une tâche | Assigné et créateur | `task_status` |
| Commentaire sur une tâche | Assigné, créateur, autres commentateurs | `task_comment` |
| Invitation à une réunion | Invités | `meeting_invite` |
| Réunion déplacée, modifiée, compte rendu publié | Participants | `meeting_updated` |
| Réunion annulée ou supprimée | Participants | `meeting_cancelled` |
| Décision proposée | Responsables du projet, organisateur | `decision_proposed` |
| Décision validée ou rejetée | Auteur de la décision | `decision_reviewed` |
| Document déposé dans un projet | Membres du projet | `document_added` |
| Ajout à un groupe privé | Membres ajoutés | `channel_added` |
| Demande d'inscription | Administrateurs | `registration_request` |
| Réponse de Ronda prête | Auteur de la question | `ai_reply` |

On ne reçoit jamais de push pour sa propre action, ni sur un projet dont on a
été retiré. Toucher la notification ouvre l'écran concerné.

**Livraison** : Firebase conserve les push jusqu'à 4 semaines si le téléphone
est éteint ou hors ligne. Si l'utilisateur a forcé l'arrêt de l'application
dans les paramètres Android, rien n'arrive avant sa prochaine ouverture ;
certains constructeurs (Xiaomi, Huawei, Oppo…) exigent aussi de désactiver
l'optimisation de batterie pour Astra Hub.

## Architecture

- `backend/app/push/` : client FCM HTTP v1 (`fcm.py`), envoi dans un thread
  dédié (`dispatcher.py`), déclenchement **après commit** (`hooks.py`).
  Toute `Notification` enregistrée part automatiquement en push.
- Table `device_tokens` et routes `PUT /devices`, `POST /devices/unregister`.
  Les jetons refusés par Firebase (application désinstallée) sont supprimés.
- Mobile : `lib/core/push/`. Le jeton est enregistré après la connexion,
  retiré à la déconnexion et invalidé à l'expiration de la session.
- Android : canaux « Messages » et « Activité » (`MainActivity.kt`), réglables
  séparément par le membre.

## Mise en place

### 1. Projet Firebase et fichiers des applications

Créer un projet sur https://console.firebase.google.com, puis y ajouter :

- une application **Android** `com.astra.astra_hub` ; télécharger
  `google-services.json` dans `mobile/android/app/` ;
- une application **iOS** `com.astra.astraHub` ; télécharger
  `GoogleService-Info.plist` dans `mobile/ios/Runner/`.

Ces fichiers ne sont **pas versionnés** (dépôt public). Sans eux, la
compilation fonctionne mais le push est désactivé.

### 2. Compte de service pour l'API

Console Firebase → Paramètres du projet → Comptes de service → « Générer une
nouvelle clé privée ». Ce fichier est un **secret** :

```bash
mv ~/Téléchargements/<projet>-firebase-adminsdk-*.json infra/secrets/firebase-service-account.json
chmod 644 infra/secrets/firebase-service-account.json   # lisible par le conteneur (uid 10001)
```

Dans `infra/.env` :

```
FIREBASE_CREDENTIALS_FILE=/run/secrets/astra/firebase-service-account.json
```

Puis `docker compose -f infra/docker-compose.yml up -d --build`. Un fichier
configuré mais illisible empêche l'API de démarrer (erreur explicite).

### 3. iOS uniquement : clé APNs

Apple exige un compte Apple Developer :

1. developer.apple.com → Keys → créer une clé avec « Apple Push Notifications
   service (APNs) », télécharger le `.p8`.
2. Console Firebase → Paramètres → Cloud Messaging → application iOS →
   importer la clé APNs (Key ID et Team ID).
3. Dans Xcode, vérifier que la capacité « Push Notifications » est active pour
   la cible Runner (l'entitlement `Runner/Runner.entitlements` est fourni).

La compilation iOS nécessite un Mac.
