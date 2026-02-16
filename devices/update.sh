#!/bin/bash
#
# devices/update.sh [оркестратор]
# Полный цикл модификации устройства: изменение полей + коммит
#
# Использование:
#   ./devices/update.sh --uuid <UUID> [--device "new_name"] [--status active|archived]
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

# Читаем имя устройства до модификации (для сообщения коммита)
DEVICE_PATH="$SIGIL_STORE_PATH/devices/${UUID}.json"
if [ ! -f "$DEVICE_PATH" ]; then
    log_error "Устройство $UUID не найдено"
    exit 1
fi
DEVICE_NAME=$(jq -r '.device' "$DEVICE_PATH")

log_info "=== Модификация устройства $DEVICE_NAME ($UUID) ===" >&2

# --- Формирование аргументов для modify.sh ---

MODIFY_ARGS=(--uuid "$UUID")
MODIFIABLE_FIELDS=(device status)
CHANGED_FIELDS=()

for FIELD in "${MODIFIABLE_FIELDS[@]}"; do
    if [ "${ARGS[$FIELD]+set}" = "set" ]; then
        MODIFY_ARGS+=(--"$FIELD" "${ARGS[$FIELD]}")
        CHANGED_FIELDS+=("$FIELD")
    fi
done

if [ ${#CHANGED_FIELDS[@]} -eq 0 ]; then
    log_error "Не указано ни одного поля для модификации"
    exit 1
fi

# [1] Модификация записи
log_info "[1/2] Модификация записи..." >&2
"$SCRIPT_DIR/modify.sh" "${MODIFY_ARGS[@]}"

# [2] Коммит
log_info "[2/2] Коммит в хранилище..." >&2
FIELDS_LIST=$(IFS=', '; echo "${CHANGED_FIELDS[*]}")
"$SCRIPT_DIR/../store/commit.sh" --message "Update device $DEVICE_NAME ($UUID): $FIELDS_LIST"

# Результат
echo "" >&2
log_success "=== Устройство $DEVICE_NAME обновлено ===" >&2
