#!/bin/bash
#
# devices/delete.sh
# Физическое удаление записи устройства из хранилища
#
# Использование:
#   ./devices/delete.sh --uuid <UUID>
#
# Выводит имя устройства в stdout (для использования в цепочке)
# Идемпотентно: exit 0 если файл не существует
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

DEVICE_PATH="$SIGIL_STORE_PATH/devices/${UUID}.json"

# Идемпотентность: если файла нет — пропуск
if [ ! -f "$DEVICE_PATH" ]; then
    log_info "Устройство $UUID не найдено, пропуск" >&2
    exit 0
fi

# Чтение имени до удаления
DEVICE_NAME=$(jq -r '.device' "$DEVICE_PATH")

rm "$DEVICE_PATH"

log_info "Устройство удалено: $DEVICE_NAME ($UUID)" >&2

# Вывод имени для использования в цепочке
echo "$DEVICE_NAME"
