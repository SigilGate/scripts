#!/bin/bash
#
# devices/create.sh
# Создание записи устройства в хранилище
#
# Использование:
#   ./devices/create.sh --user 1 --device "mobile_006"
#
# Выводит UUID созданного устройства в stdout
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

# Проверка пользователя
USER_FILE="users/${USER_ID}.json"
USER_JSON=$(store_read "users" "${USER_ID}.json") || exit 1

USER_STATUS=$(echo "$USER_JSON" | jq -r '.status')
if [ "$USER_STATUS" != "active" ]; then
    log_error "Пользователь $USER_ID не активен (статус: $USER_STATUS)"
    exit 1
fi

USERNAME=$(echo "$USER_JSON" | jq -r '.username')

# Генерация UUID
UUID=$(generate_uuid)

# Проверка уникальности UUID
DEVICE_PATH="$SIGIL_STORE_PATH/devices/${UUID}.json"
if [ -f "$DEVICE_PATH" ]; then
    log_error "Устройство с UUID $UUID уже существует"
    exit 1
fi

# Создание записи
CREATED=$(date '+%Y-%m-%d')
jq -n \
    --arg uuid "$UUID" \
    --argjson user_id "$USER_ID" \
    --arg device "$DEVICE_NAME" \
    --arg created "$CREATED" \
    '{
        uuid: $uuid,
        user_id: $user_id,
        device: $device,
        status: "active",
        created: $created
    }' > "$DEVICE_PATH"

log_info "Устройство создано: $DEVICE_NAME (пользователь: $USERNAME)"
log_info "UUID: $UUID"

# Вывод UUID для использования в цепочке
echo "$UUID"
