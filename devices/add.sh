#!/bin/bash
#
# devices/add.sh [оркестратор]
# Полный цикл добавления устройства: создание в хранилище + применение на Entry-нодах
#
# Использование:
#   ./devices/add.sh --user 1 --device "mobile_006"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[user]:-}"
DEVICE_NAME="${ARGS[device]:-}"

if [ -z "$USER_ID" ] || [ -z "$DEVICE_NAME" ]; then
    log_error "Использование: $0 --user <id> --device <name>"
    exit 1
fi

log_info "=== Добавление устройства $DEVICE_NAME для пользователя $USER_ID ==="

# [1] Создать устройство в хранилище
log_info "[1/3] Создание записи в хранилище..."
UUID=$("$SCRIPT_DIR/create.sh" --user "$USER_ID" --device "$DEVICE_NAME" | tail -1)

if [ -z "$UUID" ]; then
    log_error "Не удалось создать устройство"
    exit 1
fi

# [2] Коммит в хранилище
log_info "[2/3] Коммит в хранилище..."
USERNAME=$(store_read "users" "${USER_ID}.json" | jq -r '.username')
"$SCRIPT_DIR/../store/commit.sh" --message "Add device $DEVICE_NAME ($UUID) for user $USERNAME"

# [3] Применить на Entry-нодах
log_info "[3/3] Применение на Entry-нодах..."

ENTRY_NODES=$("$SCRIPT_DIR/../nodes/list-entry.sh" --user "$USER_ID")

VLESS_LINKS=()
ERRORS=0

while IFS= read -r NODE; do
    ENTRY_IP=$(echo "$NODE" | jq -r '.ip')
    CLIENT_SERVICE_NAME=$(echo "$NODE" | jq -r '.service_name')
    ENTRY_DOMAIN=$(echo "$NODE" | jq -r '.domain')

    if [ -z "$ENTRY_DOMAIN" ] || [ "$ENTRY_DOMAIN" = "null" ]; then
        log_error "Не найден домен для Entry-ноды $ENTRY_IP"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if "$SCRIPT_DIR/../entry/add-client.sh" \
        --host "$ENTRY_IP" \
        --uuid "$UUID" \
        --service-name "$CLIENT_SERVICE_NAME" \
        --name "$DEVICE_NAME"; then

        VLESS_LINK="vless://${UUID}@${ENTRY_DOMAIN}:443?type=grpc&security=tls&serviceName=${CLIENT_SERVICE_NAME}&fp=chrome&alpn=h2#${DEVICE_NAME}"
        VLESS_LINKS+=("$VLESS_LINK")
    else
        ERRORS=$((ERRORS + 1))
    fi
done < <(echo "$ENTRY_NODES" | jq -c '.[]')

# Результат
echo ""
log_success "=== Устройство добавлено ==="
log_info "UUID: $UUID"

if [ ${#VLESS_LINKS[@]} -gt 0 ]; then
    echo ""
    log_info "VLESS-ссылки:"
    for link in "${VLESS_LINKS[@]}"; do
        echo "$link"
    done
fi

if [ $ERRORS -gt 0 ]; then
    log_error "Ошибки при применении на $ERRORS Entry-нодах"
    exit 1
fi
