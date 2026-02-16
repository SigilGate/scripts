#!/bin/bash
#
# devices/remove.sh [оркестратор]
# Полный цикл удаления устройства: снятие с Entry-нод + удаление из хранилища + коммит
#
# Использование:
#   ./devices/remove.sh --uuid <UUID>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

UUID="${ARGS[uuid]:-}"

if [ -z "$UUID" ]; then
    log_error "Использование: $0 --uuid <UUID>"
    exit 1
fi

# --- Чтение данных устройства ---

DEVICE_JSON=$(store_read "devices" "${UUID}.json") || {
    log_error "Устройство $UUID не найдено"
    exit 1
}

DEVICE_NAME=$(echo "$DEVICE_JSON" | jq -r '.device')
USER_ID=$(echo "$DEVICE_JSON" | jq -r '.user_id')

# --- Чтение данных пользователя ---

USER_JSON=$(store_read "users" "${USER_ID}.json") || {
    log_error "Пользователь $USER_ID не найден"
    exit 1
}

USERNAME=$(echo "$USER_JSON" | jq -r '.username')
CORE_NODES=$(echo "$USER_JSON" | jq -r '.core_nodes[]')

log_info "=== Удаление устройства $DEVICE_NAME ($UUID) пользователя $USERNAME ==="

ERRORS=0

# --- [1] Снятие с Entry-нод ---

log_info "[1/3] Снятие с Entry-нод..."

for CORE_IP in $CORE_NODES; do
    for ROUTE_FILE in "$SIGIL_STORE_PATH"/routes/*.json; do
        [ -f "$ROUTE_FILE" ] || continue

        ROUTE_CORE=$(jq -r '.core_ip' "$ROUTE_FILE")
        ROUTE_STATUS=$(jq -r '.status' "$ROUTE_FILE")

        [ "$ROUTE_CORE" != "$CORE_IP" ] && continue
        [ "$ROUTE_STATUS" != "active" ] && continue

        ENTRY_IP=$(jq -r '.entry_ip' "$ROUTE_FILE")
        CLIENT_SERVICE_NAME=$(jq -r '.client_service_name' "$ROUTE_FILE")

        if ! "$SCRIPT_DIR/../entry/remove-client.sh" \
            --host "$ENTRY_IP" \
            --uuid "$UUID" \
            --service-name "$CLIENT_SERVICE_NAME"; then
            log_error "Ошибка удаления $UUID с Entry $ENTRY_IP"
            ERRORS=$((ERRORS + 1))
        fi
    done
done

# --- [2] Удаление записи из хранилища ---

log_info "[2/3] Удаление записи из хранилища..."

if ! "$SCRIPT_DIR/delete.sh" --uuid "$UUID"; then
    log_error "Ошибка удаления файла устройства $UUID"
    ERRORS=$((ERRORS + 1))
fi

# --- [3] Коммит ---

log_info "[3/3] Коммит в хранилище..."
"$SCRIPT_DIR/../store/commit.sh" --message "Remove device $DEVICE_NAME ($UUID) for user $USERNAME"

# --- Результат ---

echo ""
if [ $ERRORS -gt 0 ]; then
    log_error "=== Удаление завершено с $ERRORS ошибками ==="
    exit 1
else
    log_success "=== Устройство $DEVICE_NAME удалено ==="
fi
