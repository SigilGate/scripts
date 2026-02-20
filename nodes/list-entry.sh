#!/bin/bash
#
# nodes/list-entry.sh
# Список Entry-нод
#
# Использование:
#   ./nodes/list-entry.sh
#       Возвращает все активные Entry-ноды: [{ip, hostname, location}]
#
#   ./nodes/list-entry.sh --user <id>
#       Возвращает Entry-ноды, доступные пользователю через core_nodes → routes:
#       [{ip, hostname, location, service_name, domain}]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[user]:-}"

RESULT="[]"

if [ -z "$USER_ID" ]; then

    # --- Все активные Entry-ноды ---

    for ROLE_FILE in "$SIGIL_STORE_PATH"/roles/entry_*.json; do
        [ -f "$ROLE_FILE" ] || continue

        ROLE_STATUS=$(jq -r '.status' "$ROLE_FILE")
        [ "$ROLE_STATUS" != "active" ] && continue

        NODE_IP=$(jq -r '.node_ip' "$ROLE_FILE")
        NODE_FILE="$SIGIL_STORE_PATH/nodes/${NODE_IP}.json"
        [ -f "$NODE_FILE" ] || continue

        NODE_STATUS=$(jq -r '.status' "$NODE_FILE")
        [ "$NODE_STATUS" != "active" ] && continue

        ENTRY=$(jq -n \
            --arg ip "$NODE_IP" \
            --arg hostname "$(jq -r '.hostname' "$NODE_FILE")" \
            --arg location "$(jq -r '.location' "$NODE_FILE")" \
            '{ip: $ip, hostname: $hostname, location: $location}')

        RESULT=$(echo "$RESULT" | jq --argjson entry "$ENTRY" '. += [$entry]')
    done

else

    # --- Entry-ноды, доступные пользователю через core_nodes → routes ---

    USER_JSON=$(store_read "users" "${USER_ID}.json") || {
        log_error "Пользователь $USER_ID не найден"
        exit 1
    }

    CORE_NODES=$(echo "$USER_JSON" | jq -r '.core_nodes[]')

    for CORE_IP in $CORE_NODES; do
        for ROUTE_FILE in "$SIGIL_STORE_PATH"/routes/*.json; do
            [ -f "$ROUTE_FILE" ] || continue

            ROUTE_CORE=$(jq -r '.core_ip' "$ROUTE_FILE")
            ROUTE_STATUS=$(jq -r '.status' "$ROUTE_FILE")

            [ "$ROUTE_CORE" != "$CORE_IP" ] && continue
            [ "$ROUTE_STATUS" != "active" ] && continue

            ENTRY_IP=$(jq -r '.entry_ip' "$ROUTE_FILE")
            SERVICE_NAME=$(jq -r '.client_service_name' "$ROUTE_FILE")

            # Найти активный домен Entry-ноды
            DOMAIN=""
            for DOMAIN_FILE in "$SIGIL_STORE_PATH"/domains/*.json; do
                [ -f "$DOMAIN_FILE" ] || continue
                D_IP=$(jq -r '.node_ip' "$DOMAIN_FILE")
                D_STATUS=$(jq -r '.status' "$DOMAIN_FILE")
                if [ "$D_IP" = "$ENTRY_IP" ] && [ "$D_STATUS" = "active" ]; then
                    DOMAIN=$(jq -r '.domain' "$DOMAIN_FILE")
                    break
                fi
            done

            # Получить данные ноды
            HOSTNAME=""
            LOCATION=""
            NODE_FILE="$SIGIL_STORE_PATH/nodes/${ENTRY_IP}.json"
            if [ -f "$NODE_FILE" ]; then
                HOSTNAME=$(jq -r '.hostname' "$NODE_FILE")
                LOCATION=$(jq -r '.location' "$NODE_FILE")
            fi

            ENTRY=$(jq -n \
                --arg ip "$ENTRY_IP" \
                --arg hostname "$HOSTNAME" \
                --arg location "$LOCATION" \
                --arg service_name "$SERVICE_NAME" \
                --arg domain "$DOMAIN" \
                '{ip: $ip, hostname: $hostname, location: $location, service_name: $service_name, domain: $domain}')

            RESULT=$(echo "$RESULT" | jq --argjson entry "$ENTRY" '. += [$entry]')
        done
    done

fi

echo "$RESULT"
