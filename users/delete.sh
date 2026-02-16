#!/bin/bash
#
# users/delete.sh
# Физическое удаление записи пользователя из хранилища
#
# Использование:
#   ./users/delete.sh --id <USER_ID>
#
# Выводит username в stdout (для использования в цепочке)
# Идемпотентно: exit 0 если файл не существует
# Проверка безопасности: отказ если существуют устройства пользователя
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[id]:-}"

if [ -z "$USER_ID" ]; then
    log_error "Использование: $0 --id <ID>"
    exit 1
fi

USER_PATH="$SIGIL_STORE_PATH/users/${USER_ID}.json"

# Идемпотентность: если файла нет — пропуск
if [ ! -f "$USER_PATH" ]; then
    log_info "Пользователь $USER_ID не найден, пропуск" >&2
    exit 0
fi

USERNAME=$(jq -r '.username' "$USER_PATH")

# --- Проверка безопасности: нет ли устройств пользователя ---

ORPHAN_DEVICES=()
for DEVICE_FILE in "$SIGIL_STORE_PATH"/devices/*.json; do
    [ -f "$DEVICE_FILE" ] || continue
    DEVICE_USER=$(jq -r '.user_id' "$DEVICE_FILE")
    if [ "$DEVICE_USER" = "$USER_ID" ]; then
        ORPHAN_UUID=$(jq -r '.uuid' "$DEVICE_FILE")
        ORPHAN_DEVICES+=("$ORPHAN_UUID")
    fi
done

if [ ${#ORPHAN_DEVICES[@]} -gt 0 ]; then
    log_error "Невозможно удалить пользователя $USERNAME (ID: $USER_ID): существуют устройства:" >&2
    for d in "${ORPHAN_DEVICES[@]}"; do
        log_error "  - $d" >&2
    done
    exit 1
fi

# --- Удаление ---

rm "$USER_PATH"

log_info "Пользователь удален: $USERNAME (ID: $USER_ID)" >&2

# Вывод username для использования в цепочке
echo "$USERNAME"
