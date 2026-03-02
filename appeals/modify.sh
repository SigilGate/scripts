#!/bin/bash
#
# appeals/modify.sh
# Модификация полей записи обращения
#
# Использование:
#   ./appeals/modify.sh --id <uuid> [--status inactive|active|archived]
#                                   [--admin-telegram-id <id>]
#
# Пустое значение --admin-telegram-id ("") сбрасывает поле в null.
# Можно передать несколько полей за один вызов.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

APPEAL_ID="${ARGS[id]:-}"

if [ -z "$APPEAL_ID" ]; then
    log_error "Использование: $0 --id <uuid> [--status <status>] [--admin-telegram-id <id>]"
    exit 1
fi

APPEAL_PATH="$SIGIL_STORE_PATH/appeals/${APPEAL_ID}.json"

if [ ! -f "$APPEAL_PATH" ]; then
    log_error "Обращение $APPEAL_ID не найдено"
    exit 1
fi

# --- Определение полей для модификации ---

MODIFIABLE_FIELDS=(status admin-telegram-id)
CHANGES=()

for FIELD in "${MODIFIABLE_FIELDS[@]}"; do
    if [ "${ARGS[$FIELD]+set}" = "set" ]; then
        CHANGES+=("$FIELD")
    fi
done

if [ ${#CHANGES[@]} -eq 0 ]; then
    log_error "Не указано ни одного поля для модификации"
    log_error "Допустимые поля: ${MODIFIABLE_FIELDS[*]}"
    exit 1
fi

# --- Валидация ---

for FIELD in "${CHANGES[@]}"; do
    VALUE="${ARGS[$FIELD]}"
    case "$FIELD" in
        status)
            if [ "$VALUE" != "inactive" ] && [ "$VALUE" != "active" ] && [ "$VALUE" != "archived" ]; then
                log_error "Статус должен быть inactive, active или archived: $VALUE"
                exit 1
            fi
            ;;
        admin-telegram-id)
            if [ -n "$VALUE" ] && ! [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                log_error "admin-telegram-id должен быть положительным целым числом: $VALUE"
                exit 1
            fi
            ;;
    esac
done

# --- Применение изменений ---

TEMP_FILE=$(mktemp)
cp "$APPEAL_PATH" "$TEMP_FILE"

UPDATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

for FIELD in "${CHANGES[@]}"; do
    VALUE="${ARGS[$FIELD]}"
    case "$FIELD" in
        status)
            jq --arg val "$VALUE" '.status = $val' "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            log_info "Обращение $APPEAL_ID: status → $VALUE" >&2
            ;;
        admin-telegram-id)
            if [ -z "$VALUE" ]; then
                jq '.admin_telegram_id = null' "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
                log_info "Обращение $APPEAL_ID: admin_telegram_id → null" >&2
            else
                jq --argjson val "$VALUE" '.admin_telegram_id = $val' "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
                log_info "Обращение $APPEAL_ID: admin_telegram_id → $VALUE" >&2
            fi
            ;;
    esac
done

# Обновить поле updated
jq --arg ts "$UPDATED" '.updated = $ts' "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"

mv "$TEMP_FILE" "$APPEAL_PATH"
