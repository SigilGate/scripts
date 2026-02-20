#!/bin/bash
#
# devices/deactivate.sh [оркестратор]
# Деактивация устройства: снятие со всех Entry-нод + status=inactive + коммит
# Запись в реестре сохраняется.
#
# Использование:
#   ./devices/deactivate.sh --uuid <UUID>
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
DEVICE_STATUS=$(echo "$DEVICE_JSON" | jq -r '.status')
USER_ID=$(echo "$DEVICE_JSON" | jq -r '.user_id')

if [ "$DEVICE_STATUS" = "archived" ]; then
    log_error "Устройство $UUID архивировано, операция невозможна"
    exit 1
fi

if [ "$DEVICE_STATUS" = "inactive" ]; then
    log_info "Устройство $UUID уже неактивно"
    exit 0
fi

# --- Чтение данных пользователя ---

USER_JSON=$(store_read "users" "${USER_ID}.json") || {
    log_error "Пользователь $USER_ID не найден"
    exit 1
}

USERNAME=$(echo "$USER_JSON" | jq -r '.username')

log_info "=== Деактивация устройства $DEVICE_NAME ($UUID) пользователя $USERNAME ==="

ERRORS=0

# --- [1] Снятие с Entry-нод ---

log_info "[1/3] Снятие с Entry-нод..."

ENTRY_NODES=$("$SCRIPT_DIR/../nodes/list-entry.sh" --user "$USER_ID")

while IFS= read -r NODE; do
    ENTRY_IP=$(echo "$NODE" | jq -r '.ip')
    SERVICE_NAME=$(echo "$NODE" | jq -r '.service_name')

    if ! "$SCRIPT_DIR/../entry/remove-client.sh" \
        --host "$ENTRY_IP" \
        --uuid "$UUID" \
        --service-name "$SERVICE_NAME"; then
        log_error "Ошибка снятия $UUID с Entry $ENTRY_IP"
        ERRORS=$((ERRORS + 1))
    fi
done < <(echo "$ENTRY_NODES" | jq -c '.[]')

# --- [2] Изменение статуса ---

log_info "[2/3] Изменение статуса на inactive..."
"$SCRIPT_DIR/modify.sh" --uuid "$UUID" --status inactive

# --- [3] Коммит ---

log_info "[3/3] Коммит в хранилище..."
"$SCRIPT_DIR/../store/commit.sh" --message "Deactivate device $DEVICE_NAME ($UUID) for user $USERNAME"

# --- Результат ---

echo ""
if [ $ERRORS -gt 0 ]; then
    log_error "=== Деактивация завершена с $ERRORS ошибками ==="
    exit 1
else
    log_success "=== Устройство $DEVICE_NAME деактивировано ==="
fi
