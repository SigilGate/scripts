#!/bin/bash
#
# trial/cleanup.sh [оркестратор]
# Плановая очистка триал-устройств:
#   1. Истекает активные устройства старше --max-age секунд (по умолчанию 3600)
#   2. Прореживает архивные записи для каждого telegram_id
#
# Использование:
#   ./trial/cleanup.sh [--max-age <секунды>]
#
# Предназначен для запуска по расписанию (systemd timer, cron).
# Вызывает: trial/expire.sh, trial/prune.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

MAX_AGE="${ARGS[max-age]:-3600}"
TRIAL_USER_ID="${SIGIL_TRIAL_USER_ID:-3}"
NOW=$(date +%s)

log_info "=== Плановая очистка триал-устройств (max-age=${MAX_AGE}s) ===" >&2

EXPIRED=0
ERRORS=0

# --- [1] Истечение активных устройств ---

log_info "[1/2] Проверка активных триал-устройств..." >&2

for DEV_FILE in "$SIGIL_STORE_PATH/devices/"*.json; do
    [ -f "$DEV_FILE" ] || continue
    b=$(basename "$DEV_FILE" .json)
    [[ "$b" =~ ^[0-9a-f-]{36}$ ]] || continue

    FILE_USER_ID=$(jq -r '.user_id' "$DEV_FILE")
    [ "$FILE_USER_ID" = "$TRIAL_USER_ID" ] || continue

    DEV_STATUS=$(jq -r '.status' "$DEV_FILE")
    [ "$DEV_STATUS" = "active" ] || continue

    # Время создания определяем по mtime файла (точнее, чем поле created с датой)
    FILE_MTIME=$(stat -c %Y "$DEV_FILE")
    AGE=$((NOW - FILE_MTIME))

    if [ "$AGE" -ge "$MAX_AGE" ]; then
        UUID=$(jq -r '.uuid' "$DEV_FILE")
        DEVICE_NAME=$(jq -r '.device' "$DEV_FILE")
        log_info "Истекает: $DEVICE_NAME ($UUID), возраст=${AGE}s" >&2

        if "$SCRIPT_DIR/expire.sh" --uuid "$UUID"; then
            EXPIRED=$((EXPIRED + 1))
        else
            log_error "Ошибка при истечении устройства $UUID" >&2
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

log_info "Истекло: $EXPIRED устройств" >&2

# --- [2] Прореживание архивных записей ---

log_info "[2/2] Прореживание архивных записей..." >&2

# Собираем уникальные telegram_id из архивных устройств пользователя trial
declare -A SEEN_IDS

for DEV_FILE in "$SIGIL_STORE_PATH/devices/"*.json; do
    [ -f "$DEV_FILE" ] || continue
    b=$(basename "$DEV_FILE" .json)
    [[ "$b" =~ ^[0-9a-f-]{36}$ ]] || continue

    FILE_USER_ID=$(jq -r '.user_id' "$DEV_FILE")
    [ "$FILE_USER_ID" = "$TRIAL_USER_ID" ] || continue

    DEV_STATUS=$(jq -r '.status' "$DEV_FILE")
    [ "$DEV_STATUS" = "archived" ] || continue

    DEVICE_NAME=$(jq -r '.device' "$DEV_FILE")

    # Извлекаем telegram_id = все символы кроме последнего
    TG_ID="${DEVICE_NAME%?}"
    [[ "$TG_ID" =~ ^[0-9]+$ ]] || continue

    SEEN_IDS["$TG_ID"]=1
done

for TG_ID in "${!SEEN_IDS[@]}"; do
    log_info "Прореживание для telegram_id=$TG_ID" >&2
    "$SCRIPT_DIR/prune.sh" --telegram-id "$TG_ID" || {
        log_error "Ошибка прореживания для $TG_ID" >&2
        ERRORS=$((ERRORS + 1))
    }
done

# --- Итог ---

echo "" >&2
if [ "$ERRORS" -gt 0 ]; then
    log_error "=== Очистка завершена с $ERRORS ошибками (истекло: $EXPIRED) ===" >&2
    exit 1
else
    log_success "=== Очистка завершена успешно (истекло: $EXPIRED) ===" >&2
fi
