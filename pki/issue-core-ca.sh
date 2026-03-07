#!/bin/bash
#
# pki/issue-core-ca.sh
# Выпуск ключевой пары Core CA и деплой на Core-ноду
#
# Core CA — промежуточный CA для подписи host-сертификатов Entry-нод
# своей группы. Ключевая пара генерируется на Root-ноде и хранится
# в PKI_SSH_DIR. Приватный ключ деплоится на Core-ноду.
#
# После выполнения необходимо:
#   - Задеплоить Core CA pub key на все ноды через deploy-ca-trust.sh --core-ca
#   - Использовать core-ca ключ при issue-host-cert.sh для Entry-нод этой Core
#
# Использование:
#   ./pki/issue-core-ca.sh --host <core-ip> --identity <core-id>
#
# Пример:
#   ./pki/issue-core-ca.sh --host 128.22.161.34 --identity core-1
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
IDENTITY="${ARGS[identity]:-}"

if [ -z "$HOST" ] || [ -z "$IDENTITY" ]; then
    echo "Использование: $0 --host <ip> --identity <id>"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

PKI_DIR="${PKI_SSH_DIR:-/root/SigilGate/pki/ssh}"
CORE_CA_KEY="$PKI_DIR/$IDENTITY-ca"
CORE_CA_PUB="$PKI_DIR/$IDENTITY-ca.pub"

if [ -f "$CORE_CA_KEY" ]; then
    log_error "Core CA уже существует: $CORE_CA_KEY"
    log_info "Pub key: $CORE_CA_PUB"
    exit 1
fi

log_info "=== Выпуск Core CA → $HOST (identity: $IDENTITY) ==="

# Генерируем Core CA на Root-ноде
log_info "[1/3] Генерация Core CA ключевой пары..."
ssh-keygen -t ed25519 \
    -f "$CORE_CA_KEY" \
    -C "SigilGate Core CA ($IDENTITY)" \
    -N ""

chmod 600 "$CORE_CA_KEY"
chmod 644 "$CORE_CA_PUB"

# Деплоим приватный ключ на Core-ноду
log_info "[2/3] Деплой Core CA на $HOST..."
cat "$CORE_CA_KEY" | remote_exec "$HOST" "cat > /tmp/core_ca"
remote_exec "$HOST" "mkdir -p /home/sigil/.ssh && mv /tmp/core_ca /home/sigil/.ssh/core_ca && chmod 600 /home/sigil/.ssh/core_ca"

cat "$CORE_CA_PUB" | remote_exec "$HOST" "cat > /home/sigil/.ssh/core_ca.pub && chmod 644 /home/sigil/.ssh/core_ca.pub"

log_info "[3/3] Проверка..."
remote_exec "$HOST" "ssh-keygen -l -f /home/sigil/.ssh/core_ca.pub"

log_success "Core CA выпущен и задеплоен"
log_info "Приватный ключ (Root): $CORE_CA_KEY"
log_info "Публичный ключ (Root): $CORE_CA_PUB"
log_info "На ноде $HOST       : /home/sigil/.ssh/core_ca"
log_info ""
log_info "Следующие шаги:"
log_info "  1. Задеплоить Core CA pub key на все ноды:"
log_info "     pki/deploy-ca-trust.sh --host <ip> --core-ca $CORE_CA_PUB"
log_info "  2. Выпускать host-сертификаты для Entry-нод этой Core:"
log_info "     pki/issue-host-cert.sh --host <entry-ip> --ca $CORE_CA_KEY ..."
