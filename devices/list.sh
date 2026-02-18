#!/bin/bash
#
# devices/list.sh
# Вывод списка устройств пользователя
#
# Использование:
#   ./devices/list.sh --user <id>
#
# Выводит JSON-массив [{uuid, device, status, created}, ...] в stdout
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[user]:-}"

if [ -z "$USER_ID" ]; then
    log_error "Использование: $0 --user <id>"
    exit 1
fi

if ! [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
    log_error "user_id должен быть положительным целым числом: $USER_ID"
    exit 1
fi

entries=()
for DEV_FILE in "$SIGIL_STORE_PATH/devices/"*.json; do
    [ -f "$DEV_FILE" ] || continue
    b=$(basename "$DEV_FILE" .json)
    [[ "$b" =~ ^[0-9a-f-]{36}$ ]] || continue

    FILE_USER_ID=$(jq -r '.user_id' "$DEV_FILE")
    [ "$FILE_USER_ID" = "$USER_ID" ] || continue

    entries+=("$(jq '{uuid, device, status, created}' "$DEV_FILE")")
done

if [ ${#entries[@]} -eq 0 ]; then
    echo "[]"
else
    printf '%s\n' "${entries[@]}" | jq -s '.'
fi
