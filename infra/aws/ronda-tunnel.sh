#!/usr/bin/env bash
# Relie Ronda (llama-server sur ce PC, 127.0.0.1:8080) au backend en ligne :
# tunnel SSH inversé vers l'instance, qui ne voit Ronda que sur SON 127.0.0.1.
# Aucun port ouvert chez vous, Ronda n'est jamais exposée sur Internet.
#
#   infra/aws/ronda-tunnel.sh <ip-de-l-instance>      # se reconnecte tout seul
set -euo pipefail
IP="${1:?Usage : $0 <ip-de-l-instance>}"
KEY_FILE="${KEY_FILE:-$HOME/.ssh/astra-hub.pem}"
PORT="${RONDA_PORT:-8080}"

while true; do
    if curl -sf -m 2 "http://127.0.0.1:$PORT/health" >/dev/null; then
        echo "$(date '+%H:%M:%S') Tunnel Ronda → $IP"
        ssh -i "$KEY_FILE" -N -o ExitOnForwardFailure=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new \
            -R "127.0.0.1:$PORT:127.0.0.1:$PORT" "ubuntu@$IP" || true
    else
        echo "$(date '+%H:%M:%S') Ronda ne répond pas sur le port $PORT (lancez-la avec « ronda »)."
    fi
    sleep 10
done
