# Astra Client — cartographie d'intégration avec Astra Hub

Audit réalisé le 07/10/2026 sur `main` (110a774), en application des §72-73 du
cahier des charges Astra Client v2.0. Aucun code n'a été écrit à ce stade.

## 1. Constat de l'audit

| # | Domaine | Existant dans Astra Hub | Remarque pour Astra Client |
|---|---|---|---|
| 1 | Flutter | `mobile/` : Riverpod 3, go_router, Dio, `flutter_secure_storage`, découpage `core/` + `features/<x>/{data,presentation}`, package `com.astra.astra_hub` | Patterns réutilisables tels quels dans un nouveau projet |
| 2 | FastAPI | `api/v1` (routes minces) → `services/` (métier) → `schemas/` (`…Public`) → `models/` ; `ServiceError` → `{"detail"}` | Même découpage pour le domaine client |
| 3 | PostgreSQL | SQLAlchemy 2 + Alembic (12 migrations), UUID, `TimestampMixin`, `string_enum`, recherche `tsvector` français | — |
| 4 | Modèles | `User`, `Project`, `ProjectMember`, `Phase`, `Task`, `Meeting`, `Decision`, `Channel`, `Message`, `Notification`, `Document`, `ActivityLog`, `DeviceToken`, `RefreshToken`, IA | **Aucune** notion de client, d'entreprise, de livrable, de facture, de contrat ni de ticket |
| 5 | Authentification | JWT 15 min (`aud = astra-hub-mobile`) + refresh opaque haché, rotation, détection de réutilisation, rate limit login | Mécanisme solide, à réutiliser avec une **audience distincte** |
| 6 | Autorisations | `permissions.py` : `visible_projects_statement`, `visible_project_ids`, `get_project_role` ; 404 plutôt que 403 | À compléter par un module équivalent pour les clients |
| 7 | Rôles | `access_level` (member/manager/admin) + rôle projet (viewer/contributor/lead) | Rôles purement internes |
| 8 | Clients | Inexistant | À créer |
| 9 | Projets | `budget` exposé dans `ProjectPublic` ; pas de progression ; statuts `idea → archived` | Il faudra une représentation client dédiée |
| 10 | Documents | `Document` lié à un projet, ou **général** (`project_id` nul) et alors visible par **tout** utilisateur ; pas de visibilité ni de version | Une colonne de visibilité est indispensable |
| 11 | Fichiers | `LocalFileStorage` : noms générés, signature vérifiée, téléchargement en pièce jointe, quota d'envoi | À réutiliser tel quel |
| 12 | Notifications | Table `notifications` (FK `users`), temps réel après commit, push FCM automatique | Destinataire = `users` uniquement |
| 13 | Messagerie | Canaux public / privé / projet / direct, auteur = `users`. Les canaux publics (#général) sont visibles par tous les utilisateurs | Ne pas y mélanger les clients |
| 14 | Facturation | Inexistant | À créer |
| 15 | Contrats | Seulement `DocumentKind.CONTRACT` | À créer (l'entité ; le fichier reste un `Document`) |
| 16 | Tickets | Inexistant | À créer |
| 17 | WebSocket | `/ws`, token dans le 1er message, hub en mémoire indexé par UUID | Réutilisable via un point d'entrée dédié aux clients |
| 18 | Stockage | Volume local `/data/uploads` derrière Caddy | Pas d'URL publique : tout passe par l'API (conforme au §48) |
| 19 | UI | Thème sombre violet (`AstraColors.primary` #8B5CF6), `AsyncValueView`, `AstraAppBar` | Il faut une identité visuelle distincte (§53) |
| 20 | Conventions | Commentaires et messages en français, `ruff`, 282 tests pytest, `flutter_lints`, `mocktail` | — |

Absent également : **aucun service d'envoi d'email**. Il en faut un pour les
invitations (§8) et pour la récupération de mot de passe (§9).

## 2. Décision structurante : un principal « client » séparé de `users`

Ajouter les clients à la table `users`, par exemple avec un niveau d'accès
`client`, provoquerait des fuites dans **tout l'existant** : chaque route Hub
utilise `CurrentUser` sans filtre de ce type. Un client verrait alors :

- l'annuaire des membres (`GET /users`) ;
- les documents généraux d'Astra (`project_id IS NULL`, visibles par tous) ;
- les canaux publics (#général, #annonces) ;
- la recherche, les indicateurs « Santé d'Astra » et Ronda ;
- les tâches, phases et décisions des projets auxquels il serait rattaché.

**Proposition** :

- une table `client_accounts`, distincte de `users` ;
- des tokens JWT avec l'audience `astra-client` et `type = client_access`.

`decode_access_token` vérifie déjà l'audience. Un token client sera donc
**refusé par défaut par toutes les routes Hub**, sans les modifier : la sécurité
est assurée par construction et ne dépend pas d'un oubli de filtre. Les routes
client utilisent une dépendance `CurrentClient`, qui refuse à son tour les
tokens Hub.

## 3. Cartographie

### EXISTANT — À RÉUTILISER

| Élément | Usage côté client |
|---|---|
| `core/security.py` (hachage, refresh opaque, JWT) | Mêmes primitives, paramétrées par l'audience |
| Logique de rotation et de révocation de `auth_service` | Factorisée pour servir deux tables de comptes |
| `LocalFileStorage` + `file_types` (signatures) + `office_text` | Livrables, preuves de paiement, pièces jointes des tickets |
| `rate_limit.SlidingWindowRateLimiter` | Login client, envois de fichiers, déclarations |
| `realtime.hub` + `publish_from_thread` | Événements client (clés de connexion distinctes des membres) |
| `push.fcm` / `push.dispatcher` | Même compte de service Firebase (nouvelle app Android/iOS dans le même projet Firebase) |
| `activity_logs` (ajout seul, même transaction) | Les actions client apparaissent dans l'historique du projet côté Hub (§43) |
| `Document` + stockage | Fichiers de livrables, de contrats et de factures |
| Patterns Flutter : `AuthInterceptor` (un seul refresh), `TokenStorage`, `authRedirect`, `AsyncValueView` | Recopiés dans le projet client (voir §6) |
| Infra Docker / Caddy / `deploy.sh` | Même API, même domaine : rien à déployer en plus côté serveur |

### À MODIFIER (migrations rétrocompatibles, sans casser le Hub)

| Élément | Modification | Compatibilité |
|---|---|---|
| `projects` | `client_company_id` (FK nullable), `progress` (0-100, nullable = calculé à partir des tâches terminées), `client_summary` (texte visible du client) | Les projets existants restent internes (`NULL`) |
| `documents` | `visibility` (`internal` par défaut, `client`, `project_client`) ; `version_group_id` + `version` | Tous les documents existants restent `internal` |
| `activity_logs` | `client_account_id` (FK nullable) + contrainte « un seul acteur » | Lignes existantes inchangées |
| `push.dispatcher` / `DeviceToken` | Destinataire typé (membre ou client) | Le comportement des membres ne change pas |
| `core/security.py` | Audience et type en paramètres de `create`/`decode` | Valeurs par défaut identiques à aujourd'hui |
| `NotificationKind` (Hub) | `client_validation`, `client_change_request`, `client_message`, `ticket_created`, `payment_declared` | Ajout seul |
| Hub mobile | Écrans d'administration : entreprises, comptes et invitations, publication des livrables, visibilité des documents, conversations client, tickets, factures et vérification des paiements | Nouveaux écrans ; l'existant n'est pas touché |

### À CRÉER

**Backend** (préfixes `/api/v1/client/*` pour l'app client, `/api/v1/clients/*` et
routes associées pour le Hub) :

| Entité | Points clés |
|---|---|
| `ClientCompany` | Nom, logo, coordonnées, secteur, `is_active` |
| `ClientAccount` | `company_id`, email, mot de passe, `permissions` (tableau d'énumérations §39), `is_active`, `activated_at` |
| `ClientInvitation` | Token haché à usage unique, expiration, créé par un membre Hub |
| `ClientRefreshToken`, `ClientDeviceToken` | Mêmes règles que les membres |
| `Deliverable` / `DeliverableVersion` | Le livrable est rattaché au projet, chaque version pointe vers un `Document` ; statuts `draft → published → approved / changes_requested` |
| `DeliverableReview` | Ajout seul : compte, entreprise, version, action, commentaire, pièce jointe, horodatage (§20) |
| `ClientConversation` / `ClientMessage` | Conversation générale, liée à un projet, à un livrable ou à un ticket ; auteur = membre **ou** client (deux FK + contrainte) ; séparée des canaux internes |
| `ClientNotification` | Pendant de `notifications` pour les comptes client |
| `SupportTicket` / `TicketMessage` | Numérotation `SUP-AAAA-NNN`, types §34, statuts §35, assignation à un membre |
| `Invoice` | Numérotation `AST-AAAA-NNN`, montant, échéance, devise (XOF par défaut), document PDF ; le solde est **calculé** à partir des paiements confirmés |
| `PaymentDeclaration` | Montant, date, méthode, référence, preuve (`Document` interne lisible par le client), statuts §31, motif obligatoire en cas de refus, vérifié par un membre |
| `Contract` | Numéro, dates, statut, montant, prestations, document ; lecture seule côté client |
| `services/client_permissions.py` | Pendant de `permissions.py` : `client_visible_projects(account)` filtre **toujours** par `company_id`, puis par permission ; 404 pour toute ressource d'une autre entreprise |
| `schemas/client/*` | Représentations dédiées (`ClientProjectView`…), sans `budget`, tâches, membres internes ni notes (§40, §46) |
| Service email | Invitations et réinitialisation de mot de passe (voir les décisions D2) |
| Tests | Une suite d'isolation A → B par ressource (§70), un test par permission, un test « aucun token client n'est accepté sur les routes Hub » |

**Flutter** : nouveau projet `client/` à la racine du dépôt, à côté de `mobile/`,
package `com.astra.astra_client`. Onglets Accueil / Projets / Messages /
Documents / Plus, gestion des états du §54, deep links depuis les notifications
(§50), cache hors ligne en lecture seule (§55).

### À NE PAS TOUCHER

- Les routes Hub existantes et leurs schémas (`ProjectPublic` garde `budget`).
- `permissions.py` et ses règles membre et projet.
- Les tâches, phases, décisions, réunions, la santé d'Astra et la recherche :
  ces données restent purement internes.
- Ronda : aucune ouverture côté client avant la V3 (§69).
- Les canaux de chat internes et leurs règles (« un admin ne lit pas le privé »).
- L'application `mobile/`, en dehors de l'ajout d'écrans d'administration client.

## 4. Correspondance des statuts de projet

Le Hub reste maître du statut (§16). Les statuts client sont plus riches que
`ProjectStatus` :

| `ProjectStatus` Hub | Statut client affiché |
|---|---|
| `idea`, `planning` | Planification |
| `active` | En cours |
| `review` | En validation |
| `done` | Terminé |
| `archived` | Terminé (ou masqué) |

« En attente du client », « Modification demandée », « En correction »,
« Suspendu » et « Annulé » n'existent pas dans le Hub (voir D3).

## 5. Découpage proposé

| Lot | Contenu | Dépend de |
|---|---|---|
| 1 | Entreprises, comptes, invitations, authentification client, `CurrentClient`, `/client/me`, `/client/projects`, rattachement projet ↔ entreprise, tests d'isolation | Décisions D1-D3 |
| 2 | Livrables, versions, validations, visibilité et versions des documents, journal d'audit | 1 |
| 3 | Messagerie client, notifications client, push, WebSocket client | 1 |
| 4 | Tickets de support | 3 |
| 5 | Factures, déclarations de paiement, preuves, vérification ; contrats en lecture seule | 2 |
| 6 | Application Flutter Astra Client (démarre dès la fin du lot 1, puis suit les lots) | 1 |
| 7 | Écrans d'administration client dans Astra Hub | chaque lot backend |

## 6. Décisions (validées le 07/10/2026)

- **D1 — Principal client séparé** : table `client_accounts` et JWT d'audience
  `astra-client` (§2).
- **D2 — Emails au MVP** : aucun fournisseur. Le Hub génère un lien
  d'invitation à usage unique, que le membre transmet lui-même. La
  réinitialisation du mot de passe d'un client est déclenchée depuis le Hub
  (nouveau lien). Un fournisseur d'email pourra être branché plus tard derrière
  la même interface.
- **D3 — Statuts client** : nouveau champ `projects.client_status` piloté par le
  Hub, qui couvre les 9 statuts du §16 (`planning`, `in_progress`,
  `waiting_client`, `in_validation`, `changes_requested`, `in_correction`,
  `done`, `suspended`, `cancelled`). Il est nullable et vaut par défaut la
  correspondance du §4.
- **D4 — Flutter** : le socle réseau et authentification est recopié dans
  `client/` ; `mobile/` n'est pas modifié. Une extraction en package commun
  reste possible si les deux copies divergent.
- **D5 — Inscription libre et questionnaire de cadrage** (ajout du 07/10/2026) :
  un prospect peut créer son espace depuis Astra Client. L'inscription crée une
  **entreprise neuve et vide** (`client_companies.self_registered`), jamais
  l'accès à une entreprise existante : l'isolation du §11 reste entière.
  Il remplit ensuite le questionnaire de cadrage (repris du formulaire
  « UP DESIGN — Cahier de charge », 6 sections).

## 7. Réalisation

### Backend (`backend/app`)

| Domaine | Fichiers |
|---|---|
| Modèles | `models/client.py`, `client_enums.py`, `deliverable.py`, `client_chat.py`, `support.py`, `billing.py`, `brief.py` ; migrations `5cf6c54f6185`, `4fe702e19f5e` |
| Règles d'accès | `services/client/access.py` (client : entreprise + permission), `hub_access.py` (membres) |
| Services | `services/client/` : `auth`, `accounts`, `projects`, `deliverables`, `documents`, `conversations`, `tickets`, `billing`, `dashboard`, `briefs`, `brief_questions`, `brief_plan` |
| Routes Astra Client | `api/v1/client/*` sous `/api/v1/client` (jetons client uniquement, WebSocket `/client/ws`) |
| Routes Hub | `api/v1/clients/*` sous `/api/v1/clients` + livrables `/projects/{id}/deliverables`, `/deliverables/{id}`, partage `/documents/{id}/visibility` et `/documents/{id}/versions` |
| Tests | `tests/test_client_*.py` : isolation A → B, jetons croisés refusés, permissions, livrables, documents, messages, tickets, factures, paiements, questionnaire |

Questionnaire : la définition est servie par le serveur
(`GET /client/briefs/questionnaire`). Les deux applications affichent donc les
mêmes questions. Le plan (phases et tâches) est **déduit** des réponses par des
règles lisibles (`brief_plan.py`) : type de projet, supports, couleurs,
concurrents, échéance. Un manager le relit dans le Hub, puis crée le projet en
un clic. Le projet est alors ouvert automatiquement au client.

### Application Astra Client (`client/`)

- Package `com.astra.astra_client` (iOS `com.astra.astraClient`). Identité claire
  bleu nuit / sarcelle / ambre, mode sombre automatique.
- Responsive : barre d'onglets sur téléphone, rail sur tablette, rail étendu
  et mises en page sur deux colonnes sur grand écran. Un test balaie tous les
  écrans en 340 px, 820 px et 1440 px de large.
- États du §54 : chargement, vide, erreur, hors ligne (cache local et bandeau),
  accès refusé, introuvable, session expirée.
- Lien d'activation `astraclient://app/activate?token=…` (deep link Android/iOS),
  ou code à coller dans l'application.

### Astra Hub (`mobile/`)

- « Espace clients » (managers et administrateurs), accessible depuis le Profil
  ou le rail latéral : entreprises, comptes et liens d'invitation, cahiers des
  charges avec plan déduit, messages clients, support, vérification des
  paiements, factures, contrats.
- Projet : section « Espace client » (rattachement, statut et avancement vus
  par le client, livrables). Documents : partage avec le client.
- Responsive : rail latéral sur tablette et grand écran, largeur de lecture
  limitée, thème affiné.

## 8. Notifications push (Firebase)

**Un seul système de notifications pour les deux applications** : le projet
Firebase **`astra-f5097`** (l'ancien projet `astra-221c3` du Hub est abandonné).

| Élément | Emplacement (non versionné) |
|---|---|
| Clé serveur (compte de service) | `infra/secrets/firebase-service-account.json`, envoyée par `deploy.sh`, lue via `FIREBASE_CREDENTIALS_FILE` |
| Android (Hub + Client dans le même fichier) | `mobile/android/app/google-services.json`, `client/android/app/google-services.json` |
| iOS Hub (`com.astra.astraHub`) | `mobile/ios/Runner/GoogleService-Info.plist` |
| iOS Client (`com.astra.astraclient`) | `client/ios/Runner/GoogleService-Info.plist` |

Les applications du Hub ont été enregistrées dans `astra-f5097` le 07/10/2026
via l'API Firebase Management. Le serveur n'a besoin d'aucune modification de
code : une seule clé envoie aux deux applications.

iOS : charger la clé APNs (.p8) dans Firebase → Paramètres → Cloud Messaging,
pour les deux applications iOS.

## 9. Mises à jour des applications (Android, hors Play Store)

Au démarrage (builds release), chaque application interroge
`GET /api/v1/releases/<hub|client>/latest`. Si le build publié est plus récent
que le sien, elle propose la mise à jour : téléchargement de l'APK depuis le
serveur, vérification SHA-256, puis ouverture de l'installeur Android. La
première fois, Android demande l'autorisation « installer des applis inconnues ».

Publier une nouvelle version :

1. Incrémenter `version:` dans `mobile/pubspec.yaml` ou `client/pubspec.yaml`
   (ex. `1.1.0+2` → `1.2.0+3` ; seul le numéro après `+` compte).
2. Compiler avec l'URL de production :
   `flutter build apk --release --dart-define=API_BASE_URL=https://astra.digital-get.com/api/v1`
3. Publier : `infra/aws/publish-release.sh client <apk> "Notes de version"`
   (ajouter `--force` pour rendre la mise à jour obligatoire).

Les APK vivent sur le serveur dans `~/astra_hub/releases/<app>/`, hors du code
déployé (un redéploiement ne les efface pas). Ils sont montés en lecture seule
dans l'API (`RELEASES_DIR=/data/releases`). L'APK doit être signé avec la même
clé que l'application installée, sinon Android refuse la mise à jour.
