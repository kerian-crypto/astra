#!/usr/bin/env bash
# Déploie le backend Astra Hub sur une instance EC2 (API + PostgreSQL + Caddy/HTTPS).
#
#   AWS_PROFILE=luka infra/aws/deploy.sh            # crée l'instance ou met à jour le code
#
# Ronda n'est PAS déployée : elle reste sur le PC et rejoint l'instance par un
# tunnel SSH inversé (infra/aws/ronda-tunnel.sh). Relançable sans risque : les
# ressources existantes (étiquetées Name=astra-hub) sont réutilisées.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NAME="astra-hub"
DOMAIN="${DOMAIN:-astra.digital-get.com}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
REGION="${AWS_REGION:-$(aws configure get region || true)}"
REGION="${REGION:-eu-west-3}"
KEY_FILE="$HOME/.ssh/$NAME.pem"
export AWS_REGION="$REGION" AWS_PAGER=""

: "${AWS_PROFILE:?Définir AWS_PROFILE (ex. AWS_PROFILE=luka)}"
aws sts get-caller-identity --query Account --output text >/dev/null

log() { printf '→ %s\n' "$*" >&2; }

# ---------- Clé SSH ----------
if ! aws ec2 describe-key-pairs --key-names "$NAME" >/dev/null 2>&1; then
    log "Création de la paire de clés SSH ($KEY_FILE)"
    umask 077
    aws ec2 create-key-pair --key-name "$NAME" --key-type ed25519 \
        --query KeyMaterial --output text >"$KEY_FILE"
fi
[[ -f "$KEY_FILE" ]] || { echo "Clé $KEY_FILE absente alors que la paire existe sur AWS." >&2; exit 1; }

# ---------- Pare-feu : SSH depuis le fournisseur internet, HTTP/HTTPS pour tous ----------
# L'adresse de la box change souvent : on autorise la plage du fournisseur
# (connexion par clé uniquement, jamais par mot de passe).
SSH_CIDR="${SSH_CIDR:-129.0.0.0/16}"
VPC_ID="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"
SG_ID="$(aws ec2 describe-security-groups --filters Name=group-name,Values="$NAME" Name=vpc-id,Values="$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text)"
if [[ "$SG_ID" == "None" ]]; then
    log "Création du groupe de sécurité"
    SG_ID="$(aws ec2 create-security-group --group-name "$NAME" --vpc-id "$VPC_ID" \
        --description "Astra Hub API" --query GroupId --output text)"
    for port in 80 443; do
        aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port "$port" --cidr 0.0.0.0/0 >/dev/null
    done
fi
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$SSH_CIDR" >/dev/null 2>&1 || true

# ---------- Instance ----------
INSTANCE_ID="$(aws ec2 describe-instances --filters Name=tag:Name,Values="$NAME" \
    Name=instance-state-name,Values=pending,running,stopped \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)"
if [[ "$INSTANCE_ID" == "None" ]]; then
    AMI="$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
        --query Parameter.Value --output text)"
    log "Lancement de l'instance $INSTANCE_TYPE (Ubuntu 24.04, $REGION)"
    INSTANCE_ID="$(aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" \
        --key-name "$NAME" --security-group-ids "$SG_ID" \
        --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3,Encrypted=true}' \
        --metadata-options HttpTokens=required \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
        --query 'Instances[0].InstanceId' --output text)"
fi
aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || true
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# ---------- Adresse IP fixe ----------
ALLOC_ID="$(aws ec2 describe-addresses --filters Name=tag:Name,Values="$NAME" \
    --query 'Addresses[0].AllocationId' --output text)"
if [[ "$ALLOC_ID" == "None" ]]; then
    log "Réservation d'une Elastic IP"
    ALLOC_ID="$(aws ec2 allocate-address --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$NAME}]" \
        --query AllocationId --output text)"
fi
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$ALLOC_ID" >/dev/null
IP="$(aws ec2 describe-addresses --allocation-ids "$ALLOC_ID" --query 'Addresses[0].PublicIp' --output text)"

# ---------- Code et démarrage ----------
SSH=(ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "ubuntu@$IP")
log "Attente de SSH sur $IP"
for _ in $(seq 60); do "${SSH[@]}" true 2>/dev/null && break; sleep 5; done

log "Envoi du code (backend + infra, sans secrets locaux)"
"${SSH[@]}" "mkdir -p ~/astra_hub"
rsync -az --delete -e "ssh -i $KEY_FILE" \
    --exclude '.venv' --exclude '__pycache__' --exclude '.pytest_cache' --exclude '.ruff_cache' \
    --exclude '.coverage' --exclude '.env' --exclude 'aws' \
    "$ROOT/backend" "$ROOT/infra" "ubuntu@$IP:~/astra_hub/"
"${SSH[@]}" "DOMAIN='$DOMAIN' bash -s" <"$HERE/server-setup.sh"

log "Terminé."
echo "Instance : $INSTANCE_ID ($INSTANCE_TYPE, $REGION)"
echo "Adresse IP publique : $IP   →  enregistrement DNS A : $DOMAIN → $IP"
