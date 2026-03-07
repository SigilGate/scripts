#!/bin/bash
#
# provision/core/install-xray.sh
# Установка Xray-core на ноду
#
# Идемпотентен: если Xray уже установлен — завершается успешно.
#
# Использование:
#   ./provision/core/install-xray.sh --host <ip>
#
# Переменные окружения:
#   SIGIL_SSH_KEY, SIGIL_SSH_USER, SIGIL_SSH_PASSWORD
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"

if [ -z "$HOST" ]; then
    echo "Использование: $0 --host <ip>"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

log_info "=== Установка Xray → $HOST ==="

# Проверка — уже установлен?
if remote_exec "$HOST" "which xray" &>/dev/null; then
    VERSION=$(remote_exec "$HOST" "xray version 2>/dev/null | head -1")
    log_info "Xray уже установлен: $VERSION"
    exit 0
fi

# Установка
log_info "[1/2] Установка Xray..."
remote_sudo "$HOST" << 'REMOTE'
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
REMOTE
log_success "Xray установлен"

# Проверка
log_info "[2/2] Проверка..."
VERSION=$(remote_exec "$HOST" "xray version | head -1")
log_success "Версия: $VERSION"
log_info "Бинарник  : /usr/local/bin/xray"
log_info "Конфиг    : /usr/local/etc/xray/config.json"
log_info "Логи      : /var/log/xray/"
