# ASTRA HUB

Application mobile interne d'Astra : communication, projets, tâches, réunions,
documents et assistance IA. Vision produit complète : [docs/vision.md](docs/vision.md).
Architecture et modèle de permissions : [docs/architecture.md](docs/architecture.md).

| Dossier    | Contenu                                                  |
|------------|----------------------------------------------------------|
| `backend/` | API FastAPI + SQLAlchemy 2 + Alembic (Python 3.13, `uv`) |
| `mobile/`  | Application Flutter (Riverpod 3, go_router, Dio)         |
| `infra/`   | Docker Compose (PostgreSQL 17 + API)                     |

## Démarrage rapide

### 1. Base de données et API

```bash
cp infra/.env.example infra/.env
# Éditer infra/.env : mots de passe et SECRET_KEY (≥ 32 caractères)
#   python -c "import secrets; print(secrets.token_urlsafe(48))"
docker compose -f infra/docker-compose.yml up -d --build
```

L'API applique les migrations au démarrage puis écoute sur http://localhost:8000
(documentation interactive : http://localhost:8000/docs, désactivée en production).

### 2. Premier administrateur

Les autres membres s'inscrivent depuis l'application (« Créer un compte ») ;
un administrateur valide chaque demande et choisit le rôle (Profil → Demandes
d'inscription). Le premier administrateur se crée en ligne de commande :

```bash
docker compose -f infra/docker-compose.yml exec api \
  python -m app.cli create-admin --email vous@astra.example.com --name "Votre Nom"
```

Le mot de passe (12 caractères minimum) est demandé de façon interactive.

Créer ensuite les canaux proposés par la spec (#général, #annonces, #développement…) :

```bash
docker compose -f infra/docker-compose.yml exec api python -m app.cli seed-channels
```

### ASTRA AI avec Ronda (optionnel)

ASTRA AI utilise **Ronda**, le modèle local (Qwen3.5-4B servi par `llama-server`
de llama.cpp). Aucune donnée ne quitte la machine. Sans configuration, l'IA est
simplement désactivée et le reste de l'application fonctionne.

- Ronda sur la même machine (Linux) — l'API rejoint le réseau de l'hôte et Ronda
  reste inaccessible depuis le Wi-Fi :
  `docker compose -f infra/docker-compose.yml -f infra/docker-compose.ronda.yml up -d`
- API lancée hors Docker : `AI_BASE_URL=http://127.0.0.1:8080`
- API dans Docker : `llama-server` doit écouter sur une interface joignable par
  Docker (`--host 0.0.0.0`, port protégé par le pare-feu), puis dans `infra/.env` :
  `AI_BASE_URL=http://host.docker.internal:8080`

Sur CPU, compter ~15 s pour une réponse courte et plusieurs minutes pour un plan
de projet complet (`AI_TIMEOUT_SECONDS`, 600 par défaut).

### 3. Application mobile

```bash
cd mobile
flutter pub get
flutter run                                   # émulateur Android → http://10.0.2.2:8000
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api/v1   # appareil physique
```

Téléphone branché en USB (sans passer par le Wi-Fi) :

```bash
adb reverse tcp:8000 tcp:8000
flutter run -d <id-appareil> --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Une build release exige une URL `https://` (vérifié au démarrage).

L'icône de l'application est le « A » du logo Astra (`mobile/assets/branding/`).
Après modification : `dart run flutter_launcher_icons`.

## Développement backend

```bash
cd backend
uv sync
set -a && . ../infra/.env && set +a
export DATABASE_URL="postgresql+psycopg://$POSTGRES_USER:$POSTGRES_PASSWORD@127.0.0.1:${POSTGRES_HOST_PORT:-5432}/$POSTGRES_DB"
uv run alembic upgrade head
uv run uvicorn app.main:create_app --factory --reload
```

Nouvelle migration après modification d'un modèle :

```bash
uv run alembic revision --autogenerate -m "description"
```

## Tests

Les tests backend tournent contre une vraie base PostgreSQL **dédiée**
(elle est vidée entre chaque test) :

```bash
docker compose -f infra/docker-compose.yml exec db createdb -U astra astra_hub_test
cd backend
export TEST_DATABASE_URL="postgresql+psycopg://astra:<mot de passe>@127.0.0.1:5432/astra_hub_test"
uv run pytest --cov
uv run ruff check . && uv run ruff format --check .
```

```bash
cd mobile
flutter analyze --fatal-infos
flutter test --coverage
```

La CI GitHub Actions (`.github/workflows/ci.yml`) exécute ces mêmes vérifications,
contrôle que les migrations sont à jour avec les modèles et construit l'image Docker.
