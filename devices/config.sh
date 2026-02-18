#!/bin/bash
#
# devices/config.sh
# Генерация VLESS-ссылок для подключения устройства
#
# Использование:
#   ./devices/config.sh --uuid <uuid>
#
# Выводит JSON-массив VLESS-ссылок в stdout
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

UUID="${ARGS[uuid]:-}"

if [ -z "$UUID" ]; then
    log_error "Использование: $0 --uuid <uuid>"
    exit 1
fi

DEV_FILE="$SIGIL_STORE_PATH/devices/${UUID}.json"
if [ ! -f "$DEV_FILE" ]; then
    log_error "Устройство с UUID $UUID не найдено"
    exit 1
fi

USER_ID=$(jq -r '.user_id' "$DEV_FILE")
DEVICE_NAME=$(jq -r '.device' "$DEV_FILE")

USER_FILE="$SIGIL_STORE_PATH/users/${USER_ID}.json"
if [ ! -f "$USER_FILE" ]; then
    log_error "Пользователь $USER_ID не найден"
    exit 1
fi

CORE_NODES=$(jq -r '.core_nodes[]' "$USER_FILE" 2>/dev/null || true)

if [ -z "$CORE_NODES" ]; then
    echo "[]"
    exit 0
fi

links=()

for CORE_IP in $CORE_NODES; do
    for ROUTE_FILE in "$SIGIL_STORE_PATH/routes/"*.json; do
        [ -f "$ROUTE_FILE" ] || continue

        ROUTE_CORE=$(jq -r '.core_ip' "$ROUTE_FILE")
        ROUTE_STATUS=$(jq -r '.status' "$ROUTE_FILE")
        [ "$ROUTE_CORE" = "$CORE_IP" ] || continue
        [ "$ROUTE_STATUS" = "active" ] || continue

        ENTRY_IP=$(jq -r '.entry_ip' "$ROUTE_FILE")
        SERVICE_NAME=$(jq -r '.client_service_name' "$ROUTE_FILE")

        ENTRY_DOMAIN=""
        for DOMAIN_FILE in "$SIGIL_STORE_PATH/domains/"*.json; do
            [ -f "$DOMAIN_FILE" ] || continue
            D_IP=$(jq -r '.node_ip' "$DOMAIN_FILE")
            D_STATUS=$(jq -r '.status' "$DOMAIN_FILE")
            if [ "$D_IP" = "$ENTRY_IP" ] && [ "$D_STATUS" = "active" ]; then
                ENTRY_DOMAIN=$(jq -r '.domain' "$DOMAIN_FILE")
                break
            fi
        done

        [ -z "$ENTRY_DOMAIN" ] && continue

        LINK="vless://${UUID}@${ENTRY_DOMAIN}:443?type=grpc&security=tls&serviceName=${SERVICE_NAME}&fp=chrome&alpn=h2#${DEVICE_NAME}"
        links+=("$(printf '%s' "$LINK" | jq -Rs '.')")
    done
done

if [ ${#links[@]} -eq 0 ]; then
    echo "[]"
else
    printf '%s\n' "${links[@]}" | jq -s '.'
fi
