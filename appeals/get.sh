#!/bin/bash
#
# appeals/get.sh
# Получение обращения по ID
#
# Использование:
#   ./appeals/get.sh --id <uuid>
#
# Выводит полный JSON обращения в stdout
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

APPEAL_ID="${ARGS[id]:-}"

if [ -z "$APPEAL_ID" ]; then
    log_error "Использование: $0 --id <uuid>"
    exit 1
fi

APPEAL_PATH="$SIGIL_STORE_PATH/appeals/${APPEAL_ID}.json"

if [ ! -f "$APPEAL_PATH" ]; then
    log_error "Обращение $APPEAL_ID не найдено" >&2
    exit 1
fi

cat "$APPEAL_PATH"
