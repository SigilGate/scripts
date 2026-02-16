#!/bin/bash
#
# store/commit.sh
# Атомарный коммит изменений в хранилище (без push)
#
# Использование:
#   ./store/commit.sh --message "Add device mobile_006 for user AlexMa"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

MESSAGE="${ARGS[message]:-}"
if [ -z "$MESSAGE" ]; then
    log_error "Использование: $0 --message \"описание изменения\""
    exit 1
fi

git -C "$SIGIL_STORE_PATH" add -A

if git -C "$SIGIL_STORE_PATH" diff --cached --quiet; then
    log_info "Нет изменений для коммита" >&2
    exit 0
fi

git -C "$SIGIL_STORE_PATH" commit -m "$MESSAGE" >&2
log_success "Коммит: $MESSAGE" >&2
