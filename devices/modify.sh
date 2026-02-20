#!/bin/bash
#
# devices/modify.sh
# Модификация полей записи устройства
#
# Использование:
#   ./devices/modify.sh --uuid <UUID> [--device "new_name"] [--status active|inactive|archived]
#
# Можно передать несколько полей за один вызов.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

UUID="${ARGS[uuid]:-}"

if [ -z "$UUID" ]; then
    log_error "Использование: $0 --uuid <UUID> --<field> <value> [--<field> <value> ...]"
    exit 1
fi

DEVICE_PATH="$SIGIL_STORE_PATH/devices/${UUID}.json"

if [ ! -f "$DEVICE_PATH" ]; then
    log_error "Устройство $UUID не найдено"
    exit 1
fi

DEVICE_NAME=$(jq -r '.device' "$DEVICE_PATH")

# --- Определение полей для модификации ---

MODIFIABLE_FIELDS=(device status)
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
        device)
            if [ -z "$VALUE" ]; then
                log_error "Имя устройства не может быть пустым"
                exit 1
            fi
            ;;
        status)
            if [ "$VALUE" != "active" ] && [ "$VALUE" != "inactive" ] && [ "$VALUE" != "archived" ]; then
                log_error "Статус должен быть active, inactive или archived: $VALUE"
                exit 1
            fi
            ;;
    esac
done

# --- Применение изменений ---

TEMP_FILE=$(mktemp)
cp "$DEVICE_PATH" "$TEMP_FILE"

for FIELD in "${CHANGES[@]}"; do
    VALUE="${ARGS[$FIELD]}"
    jq --arg val "$VALUE" ".${FIELD} = \$val" "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
done

mv "$TEMP_FILE" "$DEVICE_PATH"

# --- Вывод результата ---

for FIELD in "${CHANGES[@]}"; do
    VALUE="${ARGS[$FIELD]}"
    log_info "Устройство $DEVICE_NAME ($UUID): $FIELD → $VALUE" >&2
done
