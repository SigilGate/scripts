#!/bin/bash
#
# provision/common/create-user.sh
# Создание пользователя sigil с правами sudo
#
# Запускается от начального пользователя (ubuntu/root) с паролем.
# Идемпотентен: если sigil уже существует — завершается успешно.
#
# Использование:
#   ./provision/common/create-user.sh --host <ip> --init-user <user> --init-password <pass>
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
SIGIL_PASSWORD="OpenSigilGate"

if [ -z "$HOST" ] || [ -z "$INIT_PASS" ]; then
    echo "Использование: $0 --host <ip> [--init-user ubuntu] --init-password <pass>"
    exit 1
fi

require_init_env

log_info "=== Создание пользователя sigil → $HOST ==="

# Проверяем, существует ли уже
if init_exec "$HOST" "id sigil" &>/dev/null; then
    log_info "Пользователь sigil уже существует"
    exit 0
fi

# Создаём пользователя
log_info "[1/3] Создание пользователя..."
init_sudo "$HOST" << 'REMOTE'
useradd -m -s /bin/bash sigil
usermod -aG sudo sigil
REMOTE
log_success "Пользователь sigil создан, добавлен в sudo"

# Устанавливаем пароль
log_info "[2/3] Установка пароля..."
init_sudo "$HOST" << REMOTE
echo 'sigil:$SIGIL_PASSWORD' | chpasswd
REMOTE
log_success "Пароль установлен"

# Создаём .ssh директорию
log_info "[3/3] Инициализация ~/.ssh..."
init_sudo "$HOST" << 'REMOTE'
mkdir -p /home/sigil/.ssh
chmod 700 /home/sigil/.ssh
touch /home/sigil/.ssh/authorized_keys
chmod 600 /home/sigil/.ssh/authorized_keys
chown -R sigil:sigil /home/sigil/.ssh
REMOTE
log_success "Директория ~/.ssh создана"

# Проверка
RESULT=$(init_exec "$HOST" "id sigil")
log_success "=== Пользователь sigil готов: $RESULT ==="
