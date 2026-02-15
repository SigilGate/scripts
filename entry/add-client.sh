#!/bin/bash
#
# entry/add-client.sh
# Добавление клиента (UUID) в Xray на Entry-ноде
#
# Использование:
#   ./entry/add-client.sh --host <IP> --uuid <UUID> --service-name <SERVICE_NAME> --name <LABEL>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

parse_args "$@"

HOST="${ARGS[host]:-}"
UUID="${ARGS[uuid]:-}"
SERVICE_NAME="${ARGS[service-name]:-}"
CLIENT_NAME="${ARGS[name]:-}"

if [ -z "$HOST" ] || [ -z "$UUID" ] || [ -z "$SERVICE_NAME" ] || [ -z "$CLIENT_NAME" ]; then
    log_error "Использование: $0 --host <IP> --uuid <UUID> --service-name <SERVICE_NAME> --name <LABEL>"
    exit 1
fi

XRAY_CONFIG="/usr/local/etc/xray/config.json"

log_info "Entry $HOST: добавление клиента $CLIENT_NAME"

# Проверка SSH-доступности
if ! remote_exec "$HOST" "echo OK" &>/dev/null; then
    log_error "Entry $HOST: недоступна по SSH"
    exit 1
fi

# Проверка существования UUID (идемпотентность)
EXISTS=$(remote_sudo "$HOST" <<REMOTE
cat "$XRAY_CONFIG" | jq -r \
    ".inbounds[] | select(.streamSettings.grpcSettings.serviceName == \"$SERVICE_NAME\") | .settings.clients[] | select(.id == \"$UUID\") | .id" 2>/dev/null || true
REMOTE
)

if [ "$EXISTS" = "$UUID" ]; then
    log_info "Entry $HOST: клиент $CLIENT_NAME ($UUID) уже существует"
    exit 0
fi

# Добавление клиента
remote_sudo "$HOST" <<REMOTE
set -e
BACKUP="${XRAY_CONFIG}.bak.\$(date +%Y%m%d_%H%M%S)"
cp "$XRAY_CONFIG" "\$BACKUP"

jq '(.inbounds[] | select(.streamSettings.grpcSettings.serviceName == "$SERVICE_NAME") | .settings.clients) += [{"id": "$UUID", "level": 0, "email": "$CLIENT_NAME"}]' "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp"
mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"

if ! /usr/local/bin/xray run -test -config "$XRAY_CONFIG" >/dev/null 2>&1; then
    cp "\$BACKUP" "$XRAY_CONFIG"
    echo "VALIDATION_FAILED"
    exit 1
fi

systemctl restart xray
REMOTE

# Проверка сервиса
sleep 2
XRAY_STATUS=$(remote_exec "$HOST" "systemctl is-active xray 2>/dev/null" || true)

if [ "$XRAY_STATUS" != "active" ]; then
    log_error "Entry $HOST: Xray не запущен после добавления клиента"
    exit 1
fi

log_success "Entry $HOST: клиент $CLIENT_NAME добавлен, Xray active"
