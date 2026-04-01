#!/bin/bash
#
# provision/common/harden-ssh.sh
# Усиление SSH: отключение root-входа и парольной аутентификации
#
# ВАЖНО: запускать только ПОСЛЕ успешной настройки SSH-ключа (setup-ssh-key.sh).
# После выполнения доступ возможен ТОЛЬКО по ключу для пользователя sigil.
#
# Использование:
#   ./provision/common/harden-ssh.sh --host <ip>
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

log_info "=== Усиление SSH → $HOST ==="
log_info "ВНИМАНИЕ: после выполнения — только ключ для sigil!"

# Предварительная проверка: ключ работает?
log_info "[1/3] Проверка доступа по ключу..."
if ! remote_exec "$HOST" "echo OK" 2>/dev/null | grep -q "OK"; then
    log_error "Доступ по ключу не работает! Сначала выполните setup-ssh-key.sh"
    exit 1
fi
log_success "Доступ по ключу: OK"

# Применяем настройки
log_info "[2/3] Настройка sshd_config..."
remote_sudo "$HOST" << 'REMOTE'
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

set_sshd() {
    local key="$1"
    local val="$2"
    if grep -q "^$key" /etc/ssh/sshd_config; then
        sed -i "s|^$key.*|$key $val|" /etc/ssh/sshd_config
    elif grep -q "^#$key" /etc/ssh/sshd_config; then
        sed -i "s|^#$key.*|$key $val|" /etc/ssh/sshd_config
    else
        echo "$key $val" >> /etc/ssh/sshd_config
    fi
}

set_sshd "PermitRootLogin" "no"
set_sshd "PasswordAuthentication" "no"
set_sshd "PubkeyAuthentication" "yes"
set_sshd "AuthorizedKeysFile" ".ssh/authorized_keys"

sshd -t
systemctl restart ssh 2>/dev/null || systemctl restart sshd
REMOTE
log_success "Настройки применены"

# Проверка
log_info "[3/3] Проверка..."
SETTINGS=$(remote_exec "$HOST" "grep -E '^(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin)' /etc/ssh/sshd_config")
log_info "$SETTINGS"

log_success "=== SSH защищён ==="
log_info "Доступ: только по ключу для пользователя sigil"
