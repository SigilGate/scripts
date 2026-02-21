#!/bin/bash
#
# trial/find.sh [утилита]
# Поиск триал-устройств по telegram_id пользователя
#
# Использование:
#   ./trial/find.sh --telegram-id <id> [--status active|inactive|archived]
#
# Выводит JSON-массив [{uuid, device, status, created}, ...] в stdout.
# Без --status возвращает устройства с любым статусом.
#
# Принцип именования триал-устройств: <telegram_id><цифра_лимита>
# Например: 1234569 — telegram_id=123456, лимит=9
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

TELEGRAM_ID="${ARGS[telegram-id]:-}"
STATUS_FILTER="${ARGS[status]:-}"
TRIAL_USER_ID="${SIGIL_TRIAL_USER_ID:-3}"

if [ -z "$TELEGRAM_ID" ]; then
    log_error "Использование: $0 --telegram-id <id> [--status active|inactive|archived]" >&2
    exit 1
fi

if [ -n "$STATUS_FILTER" ] && \
   [ "$STATUS_FILTER" != "active" ] && \
   [ "$STATUS_FILTER" != "inactive" ] && \
   [ "$STATUS_FILTER" != "archived" ]; then
    log_error "Допустимые значения --status: active, inactive, archived" >&2
    exit 1
fi

# Читаем все устройства пользователя trial, фильтруем по префиксу telegram_id
entries=()
for DEV_FILE in "$SIGIL_STORE_PATH/devices/"*.json; do
    [ -f "$DEV_FILE" ] || continue
    b=$(basename "$DEV_FILE" .json)
    [[ "$b" =~ ^[0-9a-f-]{36}$ ]] || continue

    FILE_USER_ID=$(jq -r '.user_id' "$DEV_FILE")
    [ "$FILE_USER_ID" = "$TRIAL_USER_ID" ] || continue

    DEVICE_NAME=$(jq -r '.device' "$DEV_FILE")

    # Имя должно начинаться с telegram_id и заканчиваться одной цифрой
    [[ "$DEVICE_NAME" =~ ^${TELEGRAM_ID}[0-9]$ ]] || continue

    # Фильтр по статусу (если задан)
    if [ -n "$STATUS_FILTER" ]; then
        DEV_STATUS=$(jq -r '.status' "$DEV_FILE")
        [ "$DEV_STATUS" = "$STATUS_FILTER" ] || continue
    fi

    entries+=("$(jq '{uuid, device, status, created}' "$DEV_FILE")")
done

if [ ${#entries[@]} -eq 0 ]; then
    echo "[]"
else
    printf '%s\n' "${entries[@]}" | jq -s '.'
fi
