#!/bin/bash
#
# provision/common/node-provision.sh
# [оркестратор] Полная базовая настройка ноды
#
# Выполняет последовательно:
#   1. system-setup.sh    — обновление системы, базовые пакеты
#   2. create-user.sh     — создание пользователя sigil
#   3. setup-ssh-key.sh   — установка SSH-ключа
#   4. harden-ssh.sh      — отключение root-входа и паролей
#   5. setup-firewall.sh  — настройка UFW
#
# Использование:
#   ./provision/common/node-provision.sh \
#     --host <ip> \
#     --role <core|entry> \
#     --init-user <user> \
#     --init-password <pass> \
#     [--pub-key <path>]
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
ROLE="${ARGS[role]:-core}"
INIT_USER="${ARGS[init-user]:-${INIT_USER:-ubuntu}}"
INIT_PASS="${ARGS[init-password]:-${INIT_PASS:-}}"
PUB_KEY="${ARGS[pub-key]:-${HOME}/.ssh/id_rsa.pub}"

if [ -z "$HOST" ] || [ -z "$INIT_PASS" ]; then
    echo "Использование: $0 --host <ip> --role <core|entry> --init-user <user> --init-password <pass> [--pub-key <path>]"
    exit 1
fi

export INIT_USER INIT_PASS

log_info "========================================"
log_info "  Базовая настройка ноды: $HOST"
log_info "  Роль: $ROLE"
log_info "========================================"

# [1/5] Система
log_info "--- [1/5] Система ---"
"$SCRIPT_DIR/system-setup.sh" \
    --host "$HOST" \
    --init-user "$INIT_USER" \
    --init-password "$INIT_PASS"

# [2/5] Пользователь sigil
log_info "--- [2/5] Пользователь sigil ---"
"$SCRIPT_DIR/create-user.sh" \
    --host "$HOST" \
    --init-user "$INIT_USER" \
    --init-password "$INIT_PASS"

# [3/5] SSH-ключ
log_info "--- [3/5] SSH-ключ ---"
"$SCRIPT_DIR/setup-ssh-key.sh" \
    --host "$HOST" \
    --init-user "$INIT_USER" \
    --init-password "$INIT_PASS" \
    --pub-key "$PUB_KEY"

# [4/5] Усиление SSH
log_info "--- [4/5] Усиление SSH ---"
"$SCRIPT_DIR/harden-ssh.sh" --host "$HOST"

# [5/5] Firewall
log_info "--- [5/5] Firewall ---"
"$SCRIPT_DIR/setup-firewall.sh" --host "$HOST" --role "$ROLE"

log_success "========================================"
log_success "  Базовая настройка завершена: $HOST"
log_success "========================================"
log_info ""
log_info "Следующие шаги (PKI):"
log_info "  pki/deploy-ca-trust.sh --host $HOST"
log_info "  pki/issue-host-cert.sh --host $HOST --identity <name> --principals <hostname>,<ip>"
log_info "  pki/issue-user-cert.sh --host $HOST"
