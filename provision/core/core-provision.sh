#!/bin/bash
#
# provision/core/core-provision.sh
# [оркестратор] Полная настройка Core-ноды
#
# Выполняет последовательно:
#   1. install-xray.sh       — установка Xray
#   2. install-nginx.sh      — установка Nginx + Certbot
#   3. setup-tls.sh          — TLS-сертификат (требует DNS A-запись)
#   4. configure-nginx.sh    — конфигурация Nginx (gRPC + прикрытие)
#   5. configure-xray.sh     — конфигурация Xray
#   6. setup-repos.sh        — клон scripts + registry
#   7. setup-services.sh     — systemd sync/rotate таймеры
#
# Использование:
#   ./provision/core/core-provision.sh \
#     --host <ip> \
#     --domain <domain> \
#     --grpc-path <path> \
#     --uuid <uuid> \
#     --github-pat <token>
#
# Пример:
#   ./provision/core/core-provision.sh \
#     --host 128.22.161.34 \
#     --domain necodate.site \
#     --grpc-path api.v2.rpc.a1b2c3d4e5f6a7b8 \
#     --uuid d2e5507d-e265-44ba-acc4-1356e4a6d70e \
#     --github-pat ghp_xxxxxxxxxxxx
#
# Переменные окружения:
#   SIGIL_SSH_KEY, SIGIL_SSH_USER, SIGIL_SSH_PASSWORD
#   GITHUB_PAT (альтернатива --github-pat)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"
DOMAIN="${ARGS[domain]:-}"
GRPC_PATH="${ARGS[grpc-path]:-}"
UUID="${ARGS[uuid]:-}"
GITHUB_PAT="${ARGS[github-pat]:-${GITHUB_PAT:-}}"

if [ -z "$HOST" ] || [ -z "$DOMAIN" ] || [ -z "$GRPC_PATH" ] || [ -z "$UUID" ] || [ -z "$GITHUB_PAT" ]; then
    echo "Использование: $0 --host <ip> --domain <domain> --grpc-path <path> --uuid <uuid> --github-pat <token>"
    exit 1
fi

log_info "========================================"
log_info "  Настройка Core-ноды: $HOST"
log_info "  Домен     : $DOMAIN"
log_info "  gRPC path : $GRPC_PATH"
log_info "========================================"

log_info "--- [1/7] Xray ---"
"$SCRIPT_DIR/install-xray.sh" --host "$HOST"

log_info "--- [2/7] Nginx + Certbot ---"
"$SCRIPT_DIR/install-nginx.sh" --host "$HOST"

log_info "--- [3/7] TLS ---"
log_info "ПАУЗА: Убедитесь, что A-запись $DOMAIN → $HOST настроена в DNS."
log_info "Нажмите Enter для продолжения или Ctrl+C для прерывания."
read -r
"$SCRIPT_DIR/setup-tls.sh" --host "$HOST" --domain "$DOMAIN"

log_info "--- [4/7] Nginx конфиг ---"
"$SCRIPT_DIR/configure-nginx.sh" \
    --host "$HOST" \
    --domain "$DOMAIN" \
    --grpc-path "$GRPC_PATH"

log_info "--- [5/7] Xray конфиг ---"
"$SCRIPT_DIR/configure-xray.sh" \
    --host "$HOST" \
    --grpc-path "$GRPC_PATH" \
    --uuid "$UUID"

log_info "--- [6/7] Репозитории ---"
"$SCRIPT_DIR/setup-repos.sh" \
    --host "$HOST" \
    --github-pat "$GITHUB_PAT"

log_info "--- [7/7] Сервисы ---"
"$SCRIPT_DIR/setup-services.sh" --host "$HOST"

log_success "========================================"
log_success "  Core-нода настроена: $HOST"
log_success "  Домен: $DOMAIN"
log_success "========================================"
log_info ""
log_info "Следующие шаги:"
log_info "  PKI: pki/issue-core-ca.sh --host $HOST --identity core-new"
log_info "  Добавить ноду в registry"
