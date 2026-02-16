#!/bin/bash
#
# users/add.sh [оркестратор]
# Полный цикл создания пользователя: создание в хранилище + коммит
#
# Использование:
#   ./users/add.sh --username "Ivan" --core-node 202.223.48.9
#
# Необязательные параметры:
#   --email user@example.com
#   --telegram @username
#   --hash "password_hash"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USERNAME="${ARGS[username]:-}"
CORE_NODE="${ARGS[core-node]:-}"

if [ -z "$USERNAME" ] || [ -z "$CORE_NODE" ]; then
    log_error "Использование: $0 --username <name> --core-node <ip>"
    exit 1
fi

log_info "=== Создание пользователя $USERNAME ===" >&2

# --- Формирование аргументов для create.sh ---

CREATE_ARGS=(--username "$USERNAME" --core-node "$CORE_NODE")

[ -n "${ARGS[email]:-}" ]    && CREATE_ARGS+=(--email "${ARGS[email]}")
[ -n "${ARGS[telegram]:-}" ] && CREATE_ARGS+=(--telegram "${ARGS[telegram]}")
[ -n "${ARGS[hash]:-}" ]     && CREATE_ARGS+=(--hash "${ARGS[hash]}")

# [1] Создать пользователя в хранилище
log_info "[1/2] Создание записи в хранилище..." >&2
NEW_ID=$("$SCRIPT_DIR/create.sh" "${CREATE_ARGS[@]}" | tail -1)

if [ -z "$NEW_ID" ]; then
    log_error "Не удалось создать пользователя"
    exit 1
fi

# [2] Коммит в хранилище
log_info "[2/2] Коммит в хранилище..." >&2
"$SCRIPT_DIR/../store/commit.sh" --message "Add user $USERNAME (ID: $NEW_ID)"

# Результат
echo "" >&2
log_success "=== Пользователь создан ===" >&2
log_info "ID: $NEW_ID" >&2
log_info "Username: $USERNAME" >&2
log_info "Core-нода: $CORE_NODE" >&2
