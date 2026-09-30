#!/usr/bin/env bash
# Crée un administrateur sur le serveur en ligne ; le mot de passe est saisi
# dans ce terminal et ne quitte jamais la connexion SSH.
#
#   infra/aws/create-admin.sh <email> "<Nom complet>"
set -euo pipefail
EMAIL="${1:?Usage : $0 <email> \"<Nom complet>\"}"
NAME="${2:?Usage : $0 <email> \"<Nom complet>\"}"
IP="${ASTRA_IP:-15.224.151.208}"
ssh -t -i "$HOME/.ssh/astra-hub.pem" "ubuntu@$IP" \
    sudo docker exec -it astra-hub-api-1 python -m app.cli create-admin \
    --email "$(printf '%q' "$EMAIL")" --name "$(printf '%q' "$NAME")"
