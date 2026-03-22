#!/bin/bash
#
# pki/issue-user-cert.sh
# Выпуск user-сертификата для sigil на ноде
#
# Получает pub key пользователя sigil, подписывает Root CA,
# деплоит сертификат обратно на ноду.
#
# Использование:
#   ./pki/issue-user-cert.sh \
#     --host <ip> \
#     [--validity <+6m>] \
#     [--identity <cert-identity>]
#
# Пример:
#   ./pki/issue-user-cert.sh --host 128.22.161.34 --validity +180d
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
VALIDITY="${ARGS[validity]:-+180d}"
IDENTITY="${ARGS[identity]:-sigil@$HOST}"
PKI_DIR="${PKI_SSH_DIR:-/root/SigilGate/pki/ssh}"
CA_KEY="$PKI_DIR/root_ca"

if [ -z "$HOST" ]; then
    echo "Использование: $0 --host <ip> [--validity +6m] [--identity <id>]"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

if [ ! -f "$CA_KEY" ]; then
    log_error "Root CA не найден: $CA_KEY. Запустите: pki/ca-init.sh"
    exit 1
fi

log_info "=== Выпуск user-сертификата → $HOST ==="
log_info "Identity : $IDENTITY"
log_info "Principal: sigil"
log_info "Validity : $VALIDITY"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Получаем pub key пользователя sigil
log_info "[1/3] Получение pub key sigil..."
remote_exec "$HOST" "cat /home/sigil/.ssh/id_ed25519.pub" > "$TMP/user_key.pub"

# Подписываем
log_info "[2/3] Подпись ключа..."
ssh-keygen -s "$CA_KEY" \
    -I "$IDENTITY" \
    -n "sigil" \
    -V "$VALIDITY" \
    "$TMP/user_key.pub"
# Результат: $TMP/user_key-cert.pub

# Деплоим сертификат (sigil может писать в свой .ssh/)
log_info "[3/3] Деплой сертификата..."
cat "$TMP/user_key-cert.pub" | remote_exec "$HOST" "cat > /home/sigil/.ssh/id_ed25519-cert.pub"
remote_exec "$HOST" "chmod 644 /home/sigil/.ssh/id_ed25519-cert.pub"

# Сохраняем копию
cp "$TMP/user_key-cert.pub" "$PKI_DIR/issued/$IDENTITY-user-cert.pub"

log_success "User-сертификат выпущен"
log_info "Срок действия : $VALIDITY"
log_info "Копия         : $PKI_DIR/issued/$IDENTITY-user-cert.pub"
log_info "Детали        : ssh-keygen -L -f $PKI_DIR/issued/$IDENTITY-user-cert.pub"
