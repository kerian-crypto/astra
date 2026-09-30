#!/usr/bin/env bash
# Exécuté SUR l'instance par deploy.sh : installe Docker, génère les secrets
# (une seule fois, jamais transmis) et (re)démarre API + PostgreSQL + Caddy.
set -euo pipefail
: "${DOMAIN:?DOMAIN manquant}"
cd ~/astra_hub/infra

if ! command -v docker >/dev/null; then
    echo "→ Installation de Docker"
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
fi

# Autorise le tunnel de Ronda à n'écouter que sur 127.0.0.1 de l'instance.
if ! grep -q '^ClientAliveInterval 30' /etc/ssh/sshd_config.d/astra.conf 2>/dev/null; then
    printf 'ClientAliveInterval 30\nClientAliveCountMax 3\nAllowTcpForwarding remote\nGatewayPorts no\n' \
        | sudo tee /etc/ssh/sshd_config.d/astra.conf >/dev/null
    sudo systemctl reload ssh
fi

if [[ ! -f .env ]]; then
    echo "→ Génération des secrets de production"
    umask 077
    cat >.env <<ENV
POSTGRES_USER=astra
POSTGRES_PASSWORD=$(openssl rand -hex 24)
POSTGRES_DB=astra_hub
POSTGRES_HOST_PORT=5432
SECRET_KEY=$(openssl rand -base64 48 | tr -d '\n')
ENVIRONMENT=production
BACKEND_CORS_ORIGINS=
DOMAIN=$DOMAIN
AI_BASE_URL=http://127.0.0.1:8080
ENV
fi

# Notifications push : clé du compte de service envoyée par deploy.sh.
FIREBASE_KEY=secrets/firebase-service-account.json
if [[ -f "$FIREBASE_KEY" ]]; then
    chmod 644 "$FIREBASE_KEY"  # lue par l'utilisateur du conteneur (uid 10001)
    if ! grep -q '^FIREBASE_CREDENTIALS_FILE=' .env; then
        echo "FIREBASE_CREDENTIALS_FILE=/run/secrets/astra/firebase-service-account.json" >>.env
    fi
fi

echo "→ Démarrage des services"
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
# Le Caddyfile est remplacé (pas modifié en place) par rsync : le conteneur
# garderait l'ancien fichier monté sans redémarrage.
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml restart caddy
sudo docker image prune -f >/dev/null
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml ps --format '{{.Service}}: {{.State}}'
