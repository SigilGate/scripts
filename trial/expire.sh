#!/bin/bash
#
# trial/expire.sh [оркестратор]
# Истечение срока одного триал-устройства: деактивация на Entry-нодах + перевод в archived
#
# Использование:
#   ./trial/expire.sh --uuid <uuid>
#
# Вызывает: devices/deactivate.sh → devices/update.sh --status archived
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

UUID="${ARGS[uuid]:-}"

if [ -z "$UUID" ]; then
    log_error "Использование: $0 --uuid <uuid>" >&2
    exit 1
fi

DEVICE_FILE="$SIGIL_STORE_PATH/devices/${UUID}.json"

if [ ! -f "$DEVICE_FILE" ]; then
    log_error "Устройство $UUID не найдено" >&2
    exit 1
fi

CURRENT_STATUS=$(jq -r '.status' "$DEVICE_FILE")
DEVICE_NAME=$(jq -r '.device' "$DEVICE_FILE")

if [ "$CURRENT_STATUS" = "archived" ]; then
    log_info "Устройство $DEVICE_NAME ($UUID) уже архивировано" >&2
    exit 0
fi

log_info "=== Истечение срока триал-устройства $DEVICE_NAME ($UUID) ===" >&2

# [1] Деактивация: снятие с Entry-нод + status=inactive + коммит
if [ "$CURRENT_STATUS" = "active" ]; then
    log_info "[1/2] Деактивация..." >&2
    "$SCRIPT_DIR/../devices/deactivate.sh" --uuid "$UUID"
fi

# [2] Перевод в archived + коммит
log_info "[2/2] Архивирование..." >&2
"$SCRIPT_DIR/../devices/update.sh" --uuid "$UUID" --status archived

log_success "=== Триал-устройство $DEVICE_NAME истекло и архивировано ===" >&2
