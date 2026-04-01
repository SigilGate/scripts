#!/bin/bash
#
# provision/common/setup-firewall.sh
# Настройка UFW (firewall)
#
# Использование:
#   ./provision/common/setup-firewall.sh --host <ip> --role <core|entry>
#
# Роли и правила:
#   core  — SSH (22), HTTP (80), HTTPS (443), outbound all
#   entry — SSH (22), HTTP (80), HTTPS (443), outbound all
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
ROLE="${ARGS[role]:-core}"

if [ -z "$HOST" ]; then
    echo "Использование: $0 --host <ip> --role <core|entry>"
    exit 1
fi

if [[ "$ROLE" != "core" && "$ROLE" != "entry" ]]; then
    log_error "Роль должна быть core или entry"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

log_info "=== Настройка firewall → $HOST (role: $ROLE) ==="

remote_sudo "$HOST" << REMOTE
set -e

# Сброс и базовые политики
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH — всегда разрешен
ufw allow 22/tcp comment "SSH"

# HTTPS — для всех ролей
ufw allow 443/tcp comment "HTTPS/gRPC"

# HTTP — для certbot (первичная выдача сертификата)
ufw allow 80/tcp comment "HTTP (certbot)"

# Включаем
ufw --force enable
ufw status verbose
REMOTE

log_success "=== Firewall настроен (role: $ROLE) ==="
