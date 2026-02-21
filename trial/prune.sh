#!/bin/bash
#
# trial/prune.sh [оркестратор]
# Прореживание архивных триал-устройств пользователя.
# Оставляет только устройство с наименьшей цифрой лимита (максимальный расход).
# Остальные архивные записи удаляются.
#
# Использование:
#   ./trial/prune.sh --telegram-id <id>
#
# Вызывает: trial/find.sh, devices/remove.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

TELEGRAM_ID="${ARGS[telegram-id]:-}"

if [ -z "$TELEGRAM_ID" ]; then
    log_error "Использование: $0 --telegram-id <id>" >&2
    exit 1
fi

# Получаем все архивные устройства данного telegram_id
ARCHIVED_JSON=$("$SCRIPT_DIR/find.sh" --telegram-id "$TELEGRAM_ID" --status archived)
COUNT=$(echo "$ARCHIVED_JSON" | jq 'length')

if [ "$COUNT" -le 1 ]; then
    log_info "Прореживание не требуется: $COUNT архивных устройств для $TELEGRAM_ID" >&2
    exit 0
fi

log_info "=== Прореживание триал-записей для telegram_id=$TELEGRAM_ID ($COUNT архивных) ===" >&2

# Находим минимальную цифру лимита (последний символ имени устройства)
MIN_DIGIT=$(echo "$ARCHIVED_JSON" | jq -r '
    [.[] | .device | .[-1:] | tonumber] | min
')

log_info "Оставляем устройство с лимитом=$MIN_DIGIT (минимальный остаток = максимальный расход)" >&2

# Флаг: уже нашли одно устройство с min-digit для сохранения
KEPT=false

DELETED=0
while IFS= read -r DEVICE; do
    UUID=$(echo "$DEVICE" | jq -r '.uuid')
    DEVICE_NAME=$(echo "$DEVICE" | jq -r '.device')
    DIGIT="${DEVICE_NAME: -1}"

    if [ "$DIGIT" = "$MIN_DIGIT" ] && [ "$KEPT" = "false" ]; then
        log_info "Сохраняем: $DEVICE_NAME ($UUID)" >&2
        KEPT=true
        continue
    fi

    log_info "Удаляем: $DEVICE_NAME ($UUID)" >&2
    "$SCRIPT_DIR/../devices/remove.sh" --uuid "$UUID"
    DELETED=$((DELETED + 1))
done < <(echo "$ARCHIVED_JSON" | jq -c '.[]')

log_success "=== Прореживание завершено: удалено $DELETED записей ===" >&2
