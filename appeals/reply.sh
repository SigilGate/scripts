#!/bin/bash
#
# appeals/reply.sh [оркестратор]
# Добавить сообщение в обращение + коммит
#
# Использование:
#   ./appeals/reply.sh --id <uuid> --from user|admin --text "Текст сообщения"
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

log_info "=== Добавление сообщения в обращение $APPEAL_ID ===" >&2

# [1] Добавить сообщение
log_info "[1/2] Запись сообщения..." >&2
"$SCRIPT_DIR/append.sh" --id "$APPEAL_ID" --from "$FROM" --text "$TEXT"

# [2] Коммит
log_info "[2/2] Коммит в хранилище..." >&2
"$SCRIPT_DIR/../store/commit.sh" --message "Appeal $APPEAL_ID: message from $FROM"

echo "" >&2
log_success "=== Сообщение добавлено ===" >&2
