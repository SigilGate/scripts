#!/bin/bash
#
# users/update.sh [оркестратор]
# Полный цикл модификации пользователя: изменение полей + коммит
#
# Использование:
#   ./users/update.sh --id <USER_ID> [--username "NewName"] [--status active|archived]
#                     [--email user@example.com] [--telegram @username]
#                     [--telegram-id 123456789] [--hash "password_hash"]
#
# Можно передать несколько полей за один вызов.
# Пустое значение ("") сбрасывает поле в null (для email, telegram, telegram-id, hash).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[id]:-}"

if [ -z "$USER_ID" ]; then
    log_error "Использование: $0 --id <ID> --<field> <value> [--<field> <value> ...]"
    exit 1
fi

# Читаем username до модификации (для сообщения коммита)
USER_PATH="$SIGIL_STORE_PATH/users/${USER_ID}.json"
if [ ! -f "$USER_PATH" ]; then
    log_error "Пользователь $USER_ID не найден"
    exit 1
fi
USERNAME=$(jq -r '.username' "$USER_PATH")

log_info "=== Модификация пользователя $USERNAME (ID: $USER_ID) ===" >&2

# --- Формирование аргументов для modify.sh ---

MODIFY_ARGS=(--id "$USER_ID")
MODIFIABLE_FIELDS=(username status email telegram telegram-id hash)
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
"$SCRIPT_DIR/../store/commit.sh" --message "Update user $USERNAME (ID: $USER_ID): $FIELDS_LIST"

# Результат
echo "" >&2
log_success "=== Пользователь $USERNAME обновлен ===" >&2
