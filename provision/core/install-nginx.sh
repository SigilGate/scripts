#!/bin/bash
#
# provision/core/install-nginx.sh
# Установка Nginx и Certbot на ноду
#
# Идемпотентен.
#
# Использование:
#   ./provision/core/install-nginx.sh --host <ip>
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

log_info "=== Установка Nginx + Certbot → $HOST ==="

remote_sudo "$HOST" << 'REMOTE'
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq nginx certbot python3-certbot-nginx
systemctl enable nginx
systemctl start nginx
REMOTE

# Проверка
NGINX_STATUS=$(remote_exec "$HOST" "systemctl is-active nginx")
log_success "Nginx: $NGINX_STATUS"
log_info "Certbot: установлен"
