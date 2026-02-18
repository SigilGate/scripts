#!/bin/bash
#
# users/list.sh
# Вывод списка пользователей из хранилища
#
# Использование:
#   ./users/list.sh [--status active|inactive|archived]
#
# Выводит JSON-массив [{id, username, status}, ...] в stdout, отсортированный по id
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

STATUS_FILTER="${ARGS[status]:-}"

if [ -n "$STATUS_FILTER" ]; then
    if [ "$STATUS_FILTER" != "active" ] && [ "$STATUS_FILTER" != "inactive" ] && [ "$STATUS_FILTER" != "archived" ]; then
        log_error "Статус должен быть active, inactive или archived: $STATUS_FILTER"
        exit 1
    fi
fi

# --- Сбор числовых ID, сортировка ---

mapfile -t USER_IDS < <(
    for f in "$SIGIL_STORE_PATH/users/"*.json; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .json)
        [[ "$b" =~ ^[0-9]+$ ]] && echo "$b"
    done 2>/dev/null | sort -n
)

# --- Фильтрация и формирование результата ---

entries=()
for USER_ID in "${USER_IDS[@]+"${USER_IDS[@]}"}"; do
    USER_FILE="$SIGIL_STORE_PATH/users/${USER_ID}.json"
    [ -f "$USER_FILE" ] || continue

    if [ -n "$STATUS_FILTER" ]; then
        FILE_STATUS=$(jq -r '.status' "$USER_FILE")
        [ "$FILE_STATUS" = "$STATUS_FILTER" ] || continue
    fi

    entries+=("$(jq '{id, username, status}' "$USER_FILE")")
done

if [ ${#entries[@]} -eq 0 ]; then
    echo "[]"
else
    printf '%s\n' "${entries[@]}" | jq -s '.'
fi
