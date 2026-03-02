#!/bin/bash
#
# appeals/create.sh
# Создание записи обращения в хранилище
#
# Использование:
#   ./appeals/create.sh --user-id 1 --username "Ivan" --telegram-id 123456789 --text "Текст обращения"
#
# Необязательные параметры:
#   --device-uuid <uuid>   Устройство, к которому относится обращение
#
# Выводит ID (UUID) созданного обращения в stdout
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[user-id]:-}"
USERNAME="${ARGS[username]:-}"
TELEGRAM_ID="${ARGS[telegram-id]:-}"
TEXT="${ARGS[text]:-}"
DEVICE_UUID="${ARGS[device-uuid]:-}"

if [ -z "$USER_ID" ] || [ -z "$USERNAME" ] || [ -z "$TELEGRAM_ID" ] || [ -z "$TEXT" ]; then
    log_error "Использование: $0 --user-id <id> --username <name> --telegram-id <id> --text <text> [--device-uuid <uuid>]"
    exit 1
fi

if ! [[ "$TELEGRAM_ID" =~ ^[0-9]+$ ]]; then
    log_error "Telegram ID должен быть положительным целым числом: $TELEGRAM_ID"
    exit 1
fi

# --- Проверка пользователя ---

USER_FILE="$SIGIL_STORE_PATH/users/${USER_ID}.json"
if [ ! -f "$USER_FILE" ]; then
    log_error "Пользователь $USER_ID не найден"
    exit 1
fi

# --- Проверка устройства (если указано) ---

if [ -n "$DEVICE_UUID" ]; then
    DEVICE_FILE="$SIGIL_STORE_PATH/devices/${DEVICE_UUID}.json"
    if [ ! -f "$DEVICE_FILE" ]; then
        log_error "Устройство $DEVICE_UUID не найдено"
        exit 1
    fi
fi

# --- Генерация ID ---

APPEAL_DIR="$SIGIL_STORE_PATH/appeals"
mkdir -p "$APPEAL_DIR"
APPEAL_ID=$(generate_uuid)

# --- Подготовка данных ---

CREATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TS="$CREATED"

# subject — первые 80 символов текста
SUBJECT="${TEXT:0:80}"

# --- Создание записи ---

APPEAL_PATH="$APPEAL_DIR/${APPEAL_ID}.json"

jq -n \
    --arg id          "$APPEAL_ID" \
    --arg user_id     "$USER_ID" \
    --arg username    "$USERNAME" \
    --argjson tg_id   "$TELEGRAM_ID" \
    --arg device_uuid "$DEVICE_UUID" \
    --arg subject     "$SUBJECT" \
    --arg created     "$CREATED" \
    --arg text        "$TEXT" \
    --arg ts          "$TS" \
    '{
        id:               $id,
        user_id:          $user_id,
        username:         $username,
        telegram_id:      $tg_id,
        device_uuid:      (if $device_uuid == "" then null else $device_uuid end),
        status:           "inactive",
        admin_telegram_id: null,
        subject:          $subject,
        created:          $created,
        updated:          $created,
        messages: [
            {
                "from": "user",
                text:   $text,
                ts:     $ts
            }
        ]
    }' > "$APPEAL_PATH"

log_info "Обращение создано: $APPEAL_ID (от $USERNAME)" >&2

echo "$APPEAL_ID"
