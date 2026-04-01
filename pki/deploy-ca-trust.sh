#!/bin/bash
#
# pki/deploy-ca-trust.sh
# Деплой доверия к SSH CA на ноду
#
# Выполняет на целевой ноде:
#   - Копирует Root CA pub key → /etc/ssh/sigil_trusted_ca
#   - Добавляет TrustedUserCAKeys и RevokedKeys в sshd_config
#   - Добавляет @cert-authority в /etc/ssh/ssh_known_hosts
#   - (Опционально) добавляет Core CA pub key в ssh_known_hosts
#   - Перезапускает sshd
#
# Использование:
#   ./pki/deploy-ca-trust.sh --host <ip> [--core-ca <path-to-pub>]
#
# Переменные окружения:
#   SIGIL_SSH_KEY, SIGIL_SSH_USER, SIGIL_SSH_PASSWORD
#   PKI_SSH_DIR (по умолчанию: /root/SigilGate/pki/ssh)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"
CORE_CA="${ARGS[core-ca]:-}"

if [ -z "$HOST" ]; then
    echo "Использование: $0 --host <ip> [--core-ca <path>]"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

PKI_DIR="${PKI_SSH_DIR:-/root/SigilGate/pki/ssh}"
ROOT_CA_PUB="$PKI_DIR/root_ca.pub"

if [ ! -f "$ROOT_CA_PUB" ]; then
    log_error "Root CA не инициализирован. Запустите: pki/ca-init.sh"
    exit 1
fi

log_info "=== Деплой CA trust → $HOST ==="

ROOT_CA_CONTENT=$(cat "$ROOT_CA_PUB")

# [1/4] Root CA pub key
log_info "[1/4] Деплой Root CA pub key..."
echo "$ROOT_CA_CONTENT" | remote_exec "$HOST" "cat > /tmp/sigil_trusted_ca"
remote_sudo "$HOST" << 'REMOTE'
mv /tmp/sigil_trusted_ca /etc/ssh/sigil_trusted_ca
chmod 644 /etc/ssh/sigil_trusted_ca
REMOTE

# [2/4] sshd_config
log_info "[2/4] Настройка sshd_config..."
remote_sudo "$HOST" << 'REMOTE'
grep -q "^TrustedUserCAKeys" /etc/ssh/sshd_config \
    || echo "TrustedUserCAKeys /etc/ssh/sigil_trusted_ca" >> /etc/ssh/sshd_config
grep -q "^RevokedKeys" /etc/ssh/sshd_config \
    || echo "RevokedKeys /etc/ssh/revoked_keys" >> /etc/ssh/sshd_config
touch /etc/ssh/revoked_keys
chmod 644 /etc/ssh/revoked_keys
REMOTE

# [3/4] ssh_known_hosts (для host-сертификатов)
log_info "[3/4] Добавление @cert-authority в ssh_known_hosts..."
KNOWN_HOSTS_LINE="@cert-authority * $ROOT_CA_CONTENT"
remote_sudo "$HOST" << REMOTE
touch /etc/ssh/ssh_known_hosts
grep -qF "SigilGate Root SSH CA" /etc/ssh/ssh_known_hosts \
    || echo "$KNOWN_HOSTS_LINE" >> /etc/ssh/ssh_known_hosts
REMOTE

# Core CA (опционально)
if [ -n "$CORE_CA" ] && [ -f "$CORE_CA" ]; then
    log_info "      Добавление Core CA..."
    CORE_CA_CONTENT=$(cat "$CORE_CA")
    remote_sudo "$HOST" << REMOTE
grep -qF "$CORE_CA_CONTENT" /etc/ssh/ssh_known_hosts \
    || echo "@cert-authority * $CORE_CA_CONTENT" >> /etc/ssh/ssh_known_hosts
REMOTE
fi

# [4/4] Перезапуск sshd
log_info "[4/4] Перезапуск sshd..."
remote_sudo "$HOST" << 'REMOTE'
sshd -t
systemctl restart ssh 2>/dev/null || systemctl restart sshd
REMOTE

log_success "CA trust задеплоен на $HOST"
