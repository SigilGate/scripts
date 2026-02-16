#!/bin/bash
#
# users/remove.sh [оркестратор]
# Полный цикл удаления пользователя: снятие всех устройств с Entry-нод + удаление устройств + удаление пользователя + коммит
#
# Использование:
#   ./users/remove.sh --id <USER_ID>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[id]:-}"

if [ -z "$USER_ID" ]; then
    log_error "Использование: $0 --id <ID>"
    exit 1
fi

# --- Чтение данных пользователя ---

USER_JSON=$(store_read "users" "${USER_ID}.json") || {
    log_error "Пользователь $USER_ID не найден"
    exit 1
}

USERNAME=$(echo "$USER_JSON" | jq -r '.username')
CORE_NODES=$(echo "$USER_JSON" | jq -r '.core_nodes[]')

# --- Поиск всех устройств пользователя ---

DEVICE_UUIDS=()
for DEVICE_FILE in "$SIGIL_STORE_PATH"/devices/*.json; do
    [ -f "$DEVICE_FILE" ] || continue
    DEVICE_USER=$(jq -r '.user_id' "$DEVICE_FILE")
    if [ "$DEVICE_USER" = "$USER_ID" ]; then
        DEVICE_UUIDS+=("$(jq -r '.uuid' "$DEVICE_FILE")")
    fi
done

DEVICE_COUNT=${#DEVICE_UUIDS[@]}
TOTAL_STEPS=$((DEVICE_COUNT + 1))
CURRENT_STEP=0
ERRORS=0

log_info "=== Удаление пользователя $USERNAME (ID: $USER_ID) ==="
log_info "Найдено устройств: $DEVICE_COUNT"

# --- Удаление устройств с Entry-нод и из хранилища ---

for UUID in "${DEVICE_UUIDS[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    DEVICE_NAME=$(jq -r '.device' "$SIGIL_STORE_PATH/devices/${UUID}.json" 2>/dev/null || echo "$UUID")

    log_info "[$CURRENT_STEP/$TOTAL_STEPS] Удаление устройства $DEVICE_NAME ($UUID)..."

    # Снятие с Entry-нод
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

    # Удаление файла устройства
    if ! "$SCRIPT_DIR/../devices/delete.sh" --uuid "$UUID"; then
        log_error "Ошибка удаления файла устройства $UUID"
        ERRORS=$((ERRORS + 1))
    fi
done

# --- Удаление пользователя ---

CURRENT_STEP=$((CURRENT_STEP + 1))
log_info "[$CURRENT_STEP/$TOTAL_STEPS] Удаление пользователя $USERNAME (ID: $USER_ID)..."

if ! "$SCRIPT_DIR/delete.sh" --id "$USER_ID"; then
    log_error "Ошибка удаления пользователя $USER_ID"
    ERRORS=$((ERRORS + 1))
fi

# --- Коммит ---

log_info "Коммит в хранилище..."
"$SCRIPT_DIR/../store/commit.sh" --message "Remove user $USERNAME (ID: $USER_ID) and $DEVICE_COUNT device(s)"

# --- Результат ---

echo ""
if [ $ERRORS -gt 0 ]; then
    log_error "=== Удаление завершено с $ERRORS ошибками ==="
    exit 1
else
    log_success "=== Пользователь $USERNAME удален ($DEVICE_COUNT устройств) ==="
fi
