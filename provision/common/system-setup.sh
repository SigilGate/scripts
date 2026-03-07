#!/bin/bash
#
# provision/common/system-setup.sh
# Обновление системы и установка базовых пакетов
#
# Запускается от начального пользователя (ubuntu/root) с паролем.
#
# Использование:
#   ./provision/common/system-setup.sh --host <ip> --init-user <user> --init-password <pass>
#
# Устанавливает:
#   sudo, curl, wget, ufw, cron, jq, git, openssl
#
# Настраивает:
#   Автообновление безопасности (ежедневно 03:00)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../lib/provision.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"
INIT_USER="${ARGS[init-user]:-${INIT_USER:-ubuntu}}"
INIT_PASS="${ARGS[init-password]:-${INIT_PASS:-}}"

if [ -z "$HOST" ] || [ -z "$INIT_PASS" ]; then
    echo "Использование: $0 --host <ip> [--init-user ubuntu] --init-password <pass>"
    exit 1
fi

require_init_env

log_info "=== Настройка системы → $HOST ==="

# [1/3] Обновление
log_info "[1/3] Обновление системы..."
init_sudo "$HOST" << 'REMOTE'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
REMOTE
log_success "Система обновлена"

# [2/3] Установка пакетов
log_info "[2/3] Установка пакетов..."
init_sudo "$HOST" << 'REMOTE'
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq sudo curl wget ufw cron jq git openssl
REMOTE
log_success "Пакеты установлены: sudo, curl, wget, ufw, cron, jq, git, openssl"

# [3/3] Автообновление безопасности
log_info "[3/3] Настройка автообновления..."
init_sudo "$HOST" << 'REMOTE'
cat > /usr/local/bin/sigil-auto-update.sh << 'SCRIPT'
#!/bin/bash
LOG=/var/log/sigil-auto-update.log
echo "=== $(date) ===" >> "$LOG"
apt-get update -qq >> "$LOG" 2>&1
apt-get upgrade -y -qq >> "$LOG" 2>&1
apt-get autoremove -y -qq >> "$LOG" 2>&1
echo "" >> "$LOG"
SCRIPT
chmod +x /usr/local/bin/sigil-auto-update.sh
echo "0 3 * * * root /usr/local/bin/sigil-auto-update.sh" > /etc/cron.d/sigil-auto-update
chmod 644 /etc/cron.d/sigil-auto-update
REMOTE
log_success "Автообновление: ежедневно в 03:00"

log_success "=== Настройка системы завершена ==="
