#!/bin/bash
#
# devices/get.sh
# Получение данных устройства по UUID
#
# Использование:
#   ./devices/get.sh --uuid <uuid>
#
# Выводит полный JSON-объект устройства в stdout
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

UUID="${ARGS[uuid]:-}"

if [ -z "$UUID" ]; then
    log_error "Использование: $0 --uuid <uuid>"
    exit 1
fi

DEV_FILE="$SIGIL_STORE_PATH/devices/${UUID}.json"

if [ ! -f "$DEV_FILE" ]; then
    log_error "Устройство с UUID $UUID не найдено"
    exit 1
fi

cat "$DEV_FILE"
