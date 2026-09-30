# Architecture

## Vue d'ensemble

```
Flutter (mobile)  ──HTTPS/JSON + WebSocket──▶  FastAPI  ──▶  PostgreSQL (+ recherche plein texte)
                                                  │
                                                  ├─ stockage des documents (volume)
                                                  └─ Ronda (llama-server local), derrière les mêmes permissions
```

Toute règle d'accès est appliquée **côté serveur**. L'application mobile masque
certaines actions (ex. bouton « Nouveau projet ») uniquement pour le confort ;
elle n'est jamais une barrière de sécurité.

## Backend

```
app/
  api/          routes HTTP minces + dépendances (auth, session DB)
  services/     logique métier ; permissions.py centralise les règles d'accès
  schemas/      modèles Pydantic d'entrée (…Create / …Update) et de sortie (…Public)
  models/       modèles SQLAlchemy
  core/         configuration, sécurité (JWT, mots de passe), rate limiting
  db/           base déclarative, session
alembic/        migrations
```

Les services lèvent des `ServiceError` (`NotFoundError`, `ConflictError`…),
convertis en réponses HTTP `{"detail": "..."}` par un gestionnaire unique.

## Modèle de permissions

### Niveau d'accès global (`users.access_level`)

| Niveau    | Droits                                                          |
|-----------|-----------------------------------------------------------------|
| `member`  | voit l'annuaire des membres actifs et ses propres projets       |
| `manager` | + crée des projets                                              |
| `admin`   | + crée/modifie/désactive les membres, accès *lead* à tout projet |

### Rôle dans un projet (`project_members.role`)

| Rôle          | Lire | Modifier le projet | Gérer les membres | Supprimer |
|---------------|:----:|:------------------:|:-----------------:|:---------:|
| `viewer`      |  ✔   |                    |                   |           |
| `contributor` |  ✔   | tâches, réunions, documents |                 |           |
| `lead`        |  ✔   |         ✔          |         ✔         |     ✔     |

Règles transverses :

- Un membre **non rattaché** à un projet reçoit `404`, pas `403` : il ne peut pas
  deviner l'existence d'un projet confidentiel.
- Un projet garde toujours au moins un `lead` ; Astra garde toujours au moins un
  `admin` actif.
- Toute requête de données projet passe par `permissions.visible_projects_statement`
  ou `project_service.get_accessible_project`. **L'IA utilise exactement ces mêmes
  fonctions** (via la recherche et « Mon travail ») : elle n'est jamais une porte
  d'accès supplémentaire aux données (spec §17).

## Inscription

- Depuis l'écran de connexion, un assistant en 6 étapes (identité, photo, poste et
  rôle souhaité, compétences, mot de passe, récapitulatif) envoie
  `POST /auth/register` (multipart).
- Le compte est créé **désactivé et en attente** ; les administrateurs sont notifiés.
  La personne peut demander « membre » ou « manager », jamais « admin » : c'est
  l'administrateur qui fixe le rôle définitif (`POST /users/{id}/approve`) ou
  refuse la demande (`POST /users/{id}/reject`, qui la supprime).
- Réponse identique si l'email existe déjà (pas d'énumération des comptes) ;
  5 demandes par heure et par IP.
- À la connexion, le message « en attente de validation » n'apparaît qu'avec le bon
  mot de passe.
- Photos de profil : PNG/JPEG vérifiés par signature, 5 Mo max, servies uniquement
  aux membres connectés (`GET /users/{id}/photo`, URL versionnée pour le cache).

## Authentification

- `POST /auth/login` → access token JWT (15 min, HS256, `iss`/`aud` vérifiés) +
  refresh token opaque (30 jours).
- Les refresh tokens sont stockés **hachés** (SHA-256) et **renouvelés à chaque
  usage**. Présenter un token déjà consommé révoque toute la session (détection de vol).
- Désactiver un membre ou changer son mot de passe révoque ses sessions ; un membre
  désactivé est refusé dès la requête suivante, même avec un access token valide.
- Le login est limité à 5 échecs / 5 min par IP + email. Le limiteur est en mémoire :
  à remplacer par Redis si l'API tourne sur plusieurs processus.

### Côté mobile

- Tokens dans `flutter_secure_storage` (Keystore Android / Keychain iOS).
- `AuthInterceptor` (Dio, `QueuedInterceptor`) ajoute le token, et sur `401`
  effectue **un seul** refresh même si plusieurs requêtes échouent en parallèle,
  puis rejoue la requête. Si le refresh est refusé, la session est effacée et le
  routeur renvoie vers l'écran de connexion. Une coupure réseau ne déconnecte pas.

## Modules (phases 2 à 5)

| Module | Points clés |
|---|---|
| Tâches | Phases ordonnées, Kanban (à faire → en cours → review → terminé), checklist, commentaires, dépendances sans cycle ; une tâche ne passe « terminée » que si ses prérequis le sont. |
| Historique | `activity_logs` : qui a fait quoi, quand, sur quel projet (journal en ajout seul, même transaction que la modification). |
| Mon travail / dashboard | Tâches du jour, en retard, prioritaires, échéances, réunions ; indicateurs Astra calculés sur les projets visibles uniquement. La date du jour est celle du téléphone. |
| Réunions | Visibles par les participants, l'organisateur et les membres du projet. Organisateur ou responsable : édition, décisions, validation. |
| Décisions | Validée → projet complet (phases, tâches) en une transaction, ou tâches. Traçabilité `decision_id` / `meeting_id` sur les tâches. |
| Messagerie | Canaux publics, groupes privés, canal automatique par projet, messages directs. **Un admin ne lit pas les conversations privées.** Mentions limitées aux personnes ayant accès au canal. |
| Temps réel | WebSocket `/ws` : le token est envoyé dans le 1er message (jamais dans l'URL), la connexion se ferme à l'expiration du token. Hub en mémoire, un par processus (Redis nécessaire pour plusieurs instances). |
| Notifications | Mention, tâche attribuée, invitation ; poussées en temps réel après commit. |
| Documents | Type déduit de l'extension et vérifié par signature, nom de stockage généré, téléchargement toujours en pièce jointe, 20 Mo max, texte extrait (PDF, texte) pour la recherche. |
| Recherche | PostgreSQL `websearch_to_tsquery('french')` sur projets, tâches, décisions, réunions, documents et messages, chaque source filtrée par sa règle de visibilité. |
| Santé d'Astra | Tâches en retard ou bloquées, dépendances critiques, membres surchargés, décisions non exécutées, informations manquantes : calculs déterministes, sans IA. |
| ASTRA AI | Ronda ne voit qu'un contexte construit par le serveur à partir des données **déjà autorisées** (§17) ; pas d'appel d'outils. Plans et comptes rendus en JSON contraint par schéma, **validés par un humain** avant toute écriture. Quota de 30 requêtes/heure par membre. |

> Note Ronda : les contraintes `maxLength`/`maxItems` d'un schéma JSON rendent la
> grammaire de llama.cpp très lente (×6 mesuré). Les schémas envoyés au modèle n'en
> ont donc pas ; les longueurs sont bornées après coup côté serveur.

## Feuille de route

| Phase | Contenu                                                        | État       |
|-------|----------------------------------------------------------------|------------|
| 0     | Fondations : Docker, migrations, secrets, CI                   | ✅ terminé |
| 1     | Membres, niveaux d'accès, JWT + refresh, accès par projet      | ✅ terminé |
| 2     | Phases, tâches, Kanban, historique, « Mon travail », dashboard | ✅ terminé |
| 3     | Réunions et décisions (décision → projet/tâches)               | ✅ terminé |
| 4     | Communication : canaux, discussions projet, notifications, temps réel | ✅ terminé |
| 5     | Documents, recherche, santé d'Astra, ASTRA AI (Ronda)          | ✅ terminé |

Pistes suivantes : notifications push (FCM/APNs), messages vocaux, pièces jointes
dans les discussions, mode hors ligne (cache local), bus Redis pour le temps réel
multi-instances, calendrier.
