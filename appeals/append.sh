#!/bin/bash
#
# appeals/append.sh
# Добавление сообщения в обращение
#
# Использование:
#   ./appeals/append.sh --id <uuid> --from user|admin --text "Текст сообщения"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

APPEAL_ID="${ARGS[id]:-}"
FROM="${ARGS[from]:-}"
TEXT="${ARGS[text]:-}"

if [ -z "$APPEAL_ID" ] || [ -z "$FROM" ] || [ -z "$TEXT" ]; then
    log_error "Использование: $0 --id <uuid> --from user|admin --text <text>"
    exit 1
fi

if [ "$FROM" != "user" ] && [ "$FROM" != "admin" ]; then
    log_error "--from должен быть user или admin: $FROM"
    exit 1
fi

APPEAL_PATH="$SIGIL_STORE_PATH/appeals/${APPEAL_ID}.json"

if [ ! -f "$APPEAL_PATH" ]; then
    log_error "Обращение $APPEAL_ID не найдено"
    exit 1
fi

# Проверяем, что обращение активно
APPEAL_STATUS=$(jq -r '.status' "$APPEAL_PATH")
if [ "$APPEAL_STATUS" != "active" ]; then
    log_error "Обращение $APPEAL_ID не активно (статус: $APPEAL_STATUS)"
    exit 1
fi

# --- Добавление сообщения ---

TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

TEMP_FILE=$(mktemp)

jq --arg from "$FROM" \
   --arg text "$TEXT" \
   --arg ts   "$TS" \
   '.messages += [{"from": $from, "text": $text, "ts": $ts}] |
    .updated = $ts' \
   "$APPEAL_PATH" > "$TEMP_FILE"

mv "$TEMP_FILE" "$APPEAL_PATH"

log_info "Сообщение добавлено в обращение $APPEAL_ID (от: $FROM)" >&2
