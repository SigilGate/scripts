#!/bin/bash
#
# pki/issue-host-cert.sh
# Выпуск host-сертификата для ноды
#
# Получает SSH host pub key ноды, подписывает Root CA (или указанным CA),
# деплоит сертификат на ноду и прописывает HostCertificate в sshd_config.
#
# Использование:
#   ./pki/issue-host-cert.sh \
#     --host <ip> \
#     --identity <cert-identity> \
#     --principals <host1,ip1,...> \
#     [--validity <+6m>] \
#     [--ca <path-to-ca-key>]
#
# Пример:
#   ./pki/issue-host-cert.sh \
#     --host 128.22.161.34 \
#     --identity core-1 \
#     --principals 128.22.161.34,core.sigilgate.internal \
#     --validity +180d
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
PRINCIPALS="${ARGS[principals]:-}"
VALIDITY="${ARGS[validity]:-+180d}"
PKI_DIR="${PKI_SSH_DIR:-/root/SigilGate/pki/ssh}"
CA_KEY="${ARGS[ca]:-$PKI_DIR/root_ca}"

if [ -z "$HOST" ] || [ -z "$IDENTITY" ] || [ -z "$PRINCIPALS" ]; then
    echo "Использование: $0 --host <ip> --identity <id> --principals <p1,p2> [--validity +6m] [--ca <key>]"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

if [ ! -f "$CA_KEY" ]; then
    log_error "CA ключ не найден: $CA_KEY"
    exit 1
fi

log_info "=== Выпуск host-сертификата → $HOST ==="
log_info "Identity  : $IDENTITY"
log_info "Principals: $PRINCIPALS"
log_info "Validity  : $VALIDITY"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Получаем host pub key (читаем напрямую, он публичный)
log_info "[1/4] Получение SSH host pub key..."
remote_exec "$HOST" "cat /etc/ssh/ssh_host_ed25519_key.pub" > "$TMP/host_key.pub"

# Подписываем
log_info "[2/4] Подпись ключа..."
ssh-keygen -s "$CA_KEY" \
    -I "$IDENTITY" \
    -h \
    -n "$PRINCIPALS" \
    -V "$VALIDITY" \
    "$TMP/host_key.pub"
# Результат: $TMP/host_key-cert.pub

# Деплоим сертификат
log_info "[3/4] Деплой сертификата..."
cat "$TMP/host_key-cert.pub" | remote_exec "$HOST" "cat > /tmp/ssh_host_ed25519_key-cert.pub"
remote_sudo "$HOST" << 'REMOTE'
mv /tmp/ssh_host_ed25519_key-cert.pub /etc/ssh/ssh_host_ed25519_key-cert.pub
chmod 644 /etc/ssh/ssh_host_ed25519_key-cert.pub
REMOTE

# Прописываем HostCertificate в sshd_config
log_info "[4/4] Настройка HostCertificate в sshd_config..."
remote_sudo "$HOST" << 'REMOTE'
grep -q "^HostCertificate" /etc/ssh/sshd_config \
    || echo "HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub" >> /etc/ssh/sshd_config
sshd -t
systemctl reload sshd
REMOTE

# Сохраняем копию
cp "$TMP/host_key-cert.pub" "$PKI_DIR/issued/$IDENTITY-host-cert.pub"

log_success "Host-сертификат выпущен"
log_info "Срок действия  : $VALIDITY"
log_info "Копия          : $PKI_DIR/issued/$IDENTITY-host-cert.pub"
log_info "Детали         : ssh-keygen -L -f $PKI_DIR/issued/$IDENTITY-host-cert.pub"
