#!/bin/bash
#
# pki/ca-init.sh
# Инициализация корневого SSH CA
#
# Создаёт ключевую пару Root CA в PKI_SSH_DIR.
# Запускается один раз на Root-ноде.
#
# Использование:
#   ./pki/ca-init.sh
#
# Переменные окружения (необязательные):
#   PKI_SSH_DIR — директория PKI (по умолчанию: /root/SigilGate/pki/ssh)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

PKI_DIR="${PKI_SSH_DIR:-/root/SigilGate/pki/ssh}"

log_info "=== Инициализация Root SSH CA ==="
log_info "Директория: $PKI_DIR"

if [ -f "$PKI_DIR/root_ca" ]; then
    log_error "CA уже инициализирован: $PKI_DIR/root_ca"
    log_info "Публичный ключ: $(cat "$PKI_DIR/root_ca.pub")"
    exit 1
fi

mkdir -p "$PKI_DIR/issued"
chmod 700 "$PKI_DIR"

log_info "Генерация Root CA (Ed25519)..."
ssh-keygen -t ed25519 \
    -f "$PKI_DIR/root_ca" \
    -C "SigilGate Root SSH CA"

chmod 600 "$PKI_DIR/root_ca"
chmod 644 "$PKI_DIR/root_ca.pub"

touch "$PKI_DIR/revoked_keys"
chmod 644 "$PKI_DIR/revoked_keys"

log_success "Root CA инициализирован"
log_info "Приватный ключ : $PKI_DIR/root_ca"
log_info "Публичный ключ : $PKI_DIR/root_ca.pub"
log_info ""
log_info "Следующие шаги:"
log_info "  1. pki/deploy-ca-trust.sh --host <ip>"
log_info "  2. pki/issue-host-cert.sh --host <ip> --identity <name> --principals <host1,ip1>"
log_info "  3. pki/issue-user-cert.sh --host <ip>"
