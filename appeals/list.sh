#!/bin/bash
#
# appeals/list.sh
# Вывод списка обращений из хранилища
#
# Использование:
#   ./appeals/list.sh [--status inactive|active|archived] [--user-id <id>]
#
# Выводит JSON-массив в stdout, отсортированный по created (новые первыми):
#   [{id, user_id, username, telegram_id, status, subject, device_uuid,
#     admin_telegram_id, created, updated}, ...]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

STATUS_FILTER="${ARGS[status]:-}"
USER_ID_FILTER="${ARGS[user-id]:-}"

if [ -n "$STATUS_FILTER" ]; then
    if [ "$STATUS_FILTER" != "inactive" ] && \
       [ "$STATUS_FILTER" != "active" ]   && \
       [ "$STATUS_FILTER" != "archived" ]; then
        log_error "Статус должен быть inactive, active или archived: $STATUS_FILTER"
        exit 1
    fi
fi

APPEALS_DIR="$SIGIL_STORE_PATH/appeals"

if [ ! -d "$APPEALS_DIR" ]; then
    echo "[]"
    exit 0
fi

entries=()

for APPEAL_FILE in "$APPEALS_DIR/"*.json; do
    [ -f "$APPEAL_FILE" ] || continue

    # Фильтр по статусу
    if [ -n "$STATUS_FILTER" ]; then
        FILE_STATUS=$(jq -r '.status' "$APPEAL_FILE")
        [ "$FILE_STATUS" = "$STATUS_FILTER" ] || continue
    fi

    # Фильтр по user_id
    if [ -n "$USER_ID_FILTER" ]; then
        FILE_USER_ID=$(jq -r '.user_id' "$APPEAL_FILE")
        [ "$FILE_USER_ID" = "$USER_ID_FILTER" ] || continue
    fi

    entries+=("$(jq '{id, user_id, username, telegram_id, status, subject, device_uuid, admin_telegram_id, created, updated}' "$APPEAL_FILE")")
done

if [ ${#entries[@]} -eq 0 ]; then
    echo "[]"
else
    printf '%s\n' "${entries[@]}" | jq -s 'sort_by(.created) | reverse'
fi
