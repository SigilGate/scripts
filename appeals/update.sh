#!/bin/bash
#
# appeals/update.sh [оркестратор]
# Изменить поля обращения + коммит
#
# Использование:
#   ./appeals/update.sh --id <uuid> [--status inactive|active|archived]
#                                   [--admin-telegram-id <id>]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

APPEAL_ID="${ARGS[id]:-}"

if [ -z "$APPEAL_ID" ]; then
    log_error "Использование: $0 --id <uuid> [--status <status>] [--admin-telegram-id <id>]"
    exit 1
fi

log_info "=== Обновление обращения $APPEAL_ID ===" >&2

# --- Формирование аргументов для modify.sh ---

MODIFY_ARGS=(--id "$APPEAL_ID")

[ "${ARGS[status]+set}" = "set" ]             && MODIFY_ARGS+=(--status             "${ARGS[status]}")
[ "${ARGS[admin-telegram-id]+set}" = "set" ]  && MODIFY_ARGS+=(--admin-telegram-id  "${ARGS[admin-telegram-id]:-}")

# [1] Применить изменения
log_info "[1/2] Обновление записи..." >&2
"$SCRIPT_DIR/modify.sh" "${MODIFY_ARGS[@]}"

# [2] Коммит
log_info "[2/2] Коммит в хранилище..." >&2

COMMIT_MSG="Update appeal $APPEAL_ID"
[ "${ARGS[status]+set}" = "set" ] && COMMIT_MSG="Update appeal $APPEAL_ID: status=${ARGS[status]}"

"$SCRIPT_DIR/../store/commit.sh" --message "$COMMIT_MSG"

echo "" >&2
log_success "=== Обращение обновлено ===" >&2
