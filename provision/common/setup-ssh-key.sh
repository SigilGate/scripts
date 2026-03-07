#!/bin/bash
#
# provision/common/setup-ssh-key.sh
# Установка SSH-ключа и генерация ключевой пары для пользователя sigil
#
# Копирует pub key с Root-ноды в authorized_keys пользователя sigil.
# Генерирует ключевую пару sigil (нужна для user-сертификатов PKI
# и для подключения sigil к другим нодам).
#
# Запускается от начального пользователя (ubuntu/root) с паролем.
#
# Использование:
#   ./provision/common/setup-ssh-key.sh --host <ip> --init-user <user> --init-password <pass> [--pub-key <path>]
#
# Параметры:
#   --pub-key  путь к pub key для авторизации (по умолчанию: ~/.ssh/id_rsa.pub)
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
PUB_KEY="${ARGS[pub-key]:-${HOME}/.ssh/id_rsa.pub}"

if [ -z "$HOST" ] || [ -z "$INIT_PASS" ]; then
    echo "Использование: $0 --host <ip> [--init-user ubuntu] --init-password <pass> [--pub-key <path>]"
    exit 1
fi

if [ ! -f "$PUB_KEY" ]; then
    log_error "Pub key не найден: $PUB_KEY"
    exit 1
fi

require_init_env

log_info "=== Установка SSH-ключа → $HOST ==="
log_info "Pub key: $PUB_KEY"

KEY_CONTENT=$(cat "$PUB_KEY")

# Добавляем pub key в authorized_keys sigil
log_info "[1/2] Добавление pub key в authorized_keys..."
init_sudo "$HOST" << REMOTE
grep -qF "$KEY_CONTENT" /home/sigil/.ssh/authorized_keys 2>/dev/null \
    || echo "$KEY_CONTENT" >> /home/sigil/.ssh/authorized_keys
chmod 600 /home/sigil/.ssh/authorized_keys
chown sigil:sigil /home/sigil/.ssh/authorized_keys
REMOTE
log_success "Pub key добавлен в authorized_keys"

# Генерируем ключевую пару для самого sigil (для PKI и межнодового SSH)
log_info "[2/2] Генерация ключевой пары sigil (Ed25519)..."
init_sudo "$HOST" << 'REMOTE'
if [ ! -f /home/sigil/.ssh/id_ed25519 ]; then
    sudo -u sigil ssh-keygen -t ed25519 -f /home/sigil/.ssh/id_ed25519 -N "" -C "sigil@sigilgate"
fi
REMOTE
log_success "Ключевая пара sigil готова"

# Проверка доступа по ключу
log_info "Проверка доступа по ключу..."
if ssh -o StrictHostKeyChecking=no \
       -o ConnectTimeout=10 \
       -o BatchMode=yes \
       -i "${PUB_KEY%.pub}" \
       "sigil@$HOST" "echo OK" 2>/dev/null | grep -q "OK"; then
    log_success "Доступ по ключу работает"
else
    log_error "Доступ по ключу не работает! Проверьте ключ и authorized_keys"
    exit 1
fi

log_success "=== SSH-ключ установлен ==="
