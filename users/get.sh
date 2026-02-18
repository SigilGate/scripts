#!/bin/bash
#
# users/get.sh
# Получение данных пользователя по ID
#
# Использование:
#   ./users/get.sh --id <id>
#
# Выводит полный JSON-объект пользователя в stdout
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[id]:-}"

if [ -z "$USER_ID" ]; then
    log_error "Использование: $0 --id <id>"
    exit 1
fi

if ! [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
    log_error "ID должен быть положительным целым числом: $USER_ID"
    exit 1
fi

USER_FILE="$SIGIL_STORE_PATH/users/${USER_ID}.json"

if [ ! -f "$USER_FILE" ]; then
    log_error "Пользователь с ID $USER_ID не найден"
    exit 1
fi

cat "$USER_FILE"
