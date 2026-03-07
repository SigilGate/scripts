#!/bin/bash
#
# pki/revoke-cert.sh
# Отзыв SSH-сертификата или ключа
#
# Добавляет ключ/сертификат в revoked_keys и деплоит обновлённый файл
# на указанные ноды. sshd проверяет revoked_keys при каждом подключении.
#
# Использование:
#   ./pki/revoke-cert.sh --pubkey <path> --hosts <ip1,ip2,...>
#
# Параметры:
#   --pubkey  путь к pub key или cert pub key для отзыва
#   --hosts   список IP через запятую (или "all" — из registry)
#
# Пример:
#   ./pki/revoke-cert.sh --pubkey /root/SigilGate/pki/ssh/issued/core-1-host-cert.pub --hosts 128.22.161.34,195.2.67.202
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

PUBKEY="${ARGS[pubkey]:-}"
HOSTS_ARG="${ARGS[hosts]:-}"

if [ -z "$PUBKEY" ] || [ -z "$HOSTS_ARG" ]; then
    echo "Использование: $0 --pubkey <path> --hosts <ip1,ip2,...>"
    exit 1
fi

if [ ! -f "$PUBKEY" ]; then
    log_error "Файл не найден: $PUBKEY"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

PKI_DIR="${PKI_SSH_DIR:-/root/SigilGate/pki/ssh}"
REVOKED_KEYS="$PKI_DIR/revoked_keys"

log_info "=== Отзыв ключа/сертификата ==="
log_info "Файл: $PUBKEY"

# Добавляем в revoked_keys
log_info "[1/2] Обновление revoked_keys..."
ssh-keygen -k -f "$REVOKED_KEYS" -u "$PUBKEY"
log_success "Ключ добавлен в $REVOKED_KEYS"

# Деплоим на ноды
log_info "[2/2] Деплой revoked_keys на ноды..."
IFS=',' read -ra HOSTS <<< "$HOSTS_ARG"
for HOST in "${HOSTS[@]}"; do
    HOST=$(echo "$HOST" | xargs)
    log_info "  → $HOST"
    cat "$REVOKED_KEYS" | remote_exec "$HOST" "cat > /tmp/revoked_keys"
    remote_sudo "$HOST" << 'REMOTE'
mv /tmp/revoked_keys /etc/ssh/revoked_keys
chmod 644 /etc/ssh/revoked_keys
REMOTE
    log_success "  $HOST: обновлено"
done

log_success "Отзыв завершён"
