#!/usr/bin/env bash
# Publie une nouvelle version Android sur le serveur : les applications
# installées la proposent au démarrage (GET /api/v1/releases/<app>/latest).
#
#   infra/aws/publish-release.sh client astra_client.apk "Corrections et nouveautés"
#   infra/aws/publish-release.sh hub astra_hub.apk "Notes" --force   # mise à jour obligatoire
#
# La version et le numéro de build sont lus dans le pubspec.yaml de l'app :
# incrémenter le « +N » de `version:` avant de compiler l'APK.
set -euo pipefail

APP="${1:?app : hub ou client}"
APK="${2:?chemin de l’APK}"
NOTES="${3:-}"
FORCE="${4:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST="${DEPLOY_HOST:-ubuntu@astra.digital-get.com}"
KEY_FILE="${KEY_FILE:-$HOME/.ssh/astra-hub.pem}"
SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

case "$APP" in
    hub) PUBSPEC="$ROOT/mobile/pubspec.yaml" ;;
    client) PUBSPEC="$ROOT/client/pubspec.yaml" ;;
    *) echo "app inconnue : $APP (hub ou client)" >&2; exit 1 ;;
esac
[[ -f "$APK" ]] || { echo "APK introuvable : $APK" >&2; exit 1; }

FULL_VERSION="$(sed -n 's/^version: *\([^ ]*\).*/\1/p' "$PUBSPEC")"
VERSION="${FULL_VERSION%%+*}"
BUILD="${FULL_VERSION##*+}"
FILE="astra_${APP}-${VERSION}+${BUILD}.apk"
MIN_BUILD=1
[[ "$FORCE" == "--force" ]] && MIN_BUILD="$BUILD"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$APK" "$STAGE/$FILE"
python3 - "$STAGE" "$FILE" "$VERSION" "$BUILD" "$MIN_BUILD" "$NOTES" <<'PY'
import hashlib, json, os, sys
stage, file, version, build, min_build, notes = sys.argv[1:]
path = os.path.join(stage, file)
digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
json.dump({
    "version": version, "build_number": int(build), "min_build_number": int(min_build),
    "notes": notes or None, "file": file, "size_bytes": os.path.getsize(path), "sha256": digest,
}, open(os.path.join(stage, "release.json"), "w"), ensure_ascii=False, indent=2)
PY

echo "→ Publication de $APP $VERSION (build $BUILD) sur $HOST"
ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p ~/astra_hub/releases/$APP"
# L'APK d'abord, le manifeste ensuite : une app ne voit jamais un manifeste
# qui pointe vers un fichier pas encore arrivé. Les anciens APK sont supprimés.
rsync -az -e "ssh ${SSH_OPTS[*]}" "$STAGE/$FILE" "$HOST:~/astra_hub/releases/$APP/"
rsync -az -e "ssh ${SSH_OPTS[*]}" "$STAGE/release.json" "$HOST:~/astra_hub/releases/$APP/"
ssh "${SSH_OPTS[@]}" "$HOST" "cd ~/astra_hub/releases/$APP && ls *.apk | grep -vxF '$FILE' | xargs -r rm -f"
echo "→ Publié : https://astra.digital-get.com/api/v1/releases/$APP/latest"
