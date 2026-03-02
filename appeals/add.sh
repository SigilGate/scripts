#!/bin/bash
#
# appeals/add.sh [оркестратор]
# Полный цикл создания обращения: запись в хранилище + коммит
#
# Использование:
#   ./appeals/add.sh --user-id 1 --username "Ivan" --telegram-id 123456789 --text "Текст"
#
# Необязательные параметры:
#   --device-uuid <uuid>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USER_ID="${ARGS[user-id]:-}"
USERNAME="${ARGS[username]:-}"
TELEGRAM_ID="${ARGS[telegram-id]:-}"
TEXT="${ARGS[text]:-}"

if [ -z "$USER_ID" ] || [ -z "$USERNAME" ] || [ -z "$TELEGRAM_ID" ] || [ -z "$TEXT" ]; then
    log_error "Использование: $0 --user-id <id> --username <name> --telegram-id <id> --text <text> [--device-uuid <uuid>]"
    exit 1
fi

log_info "=== Создание обращения от $USERNAME ===" >&2

# --- Формирование аргументов для create.sh ---

CREATE_ARGS=(
    --user-id     "$USER_ID"
    --username    "$USERNAME"
    --telegram-id "$TELEGRAM_ID"
    --text        "$TEXT"
)

[ -n "${ARGS[device-uuid]:-}" ] && CREATE_ARGS+=(--device-uuid "${ARGS[device-uuid]}")

# [1] Создать запись
log_info "[1/2] Создание записи в хранилище..." >&2
APPEAL_ID=$("$SCRIPT_DIR/create.sh" "${CREATE_ARGS[@]}" | tail -1)

if [ -z "$APPEAL_ID" ]; then
    log_error "Не удалось создать обращение"
    exit 1
fi

# [2] Коммит
log_info "[2/2] Коммит в хранилище..." >&2
"$SCRIPT_DIR/../store/commit.sh" --message "Open appeal $APPEAL_ID from $USERNAME"

echo "" >&2
log_success "=== Обращение создано ===" >&2
log_info "ID: $APPEAL_ID" >&2
log_info "От: $USERNAME (user_id: $USER_ID)" >&2

echo "$APPEAL_ID"
