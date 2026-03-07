#!/bin/bash
#
# provision/core/setup-services.sh
# Установка и активация systemd-сервисов Core-ноды
#
# Устанавливает:
#   - sigilgate-sync.timer  — синхронизация репозиториев (каждые 15 мин)
#   - sigilgate-rotate.timer — ротация gRPC-пути (по расписанию)
#
# Шаблоны берутся из scripts-репозитория, плейсхолдеры заменяются
# реальными путями.
#
# Использование:
#   ./provision/core/setup-services.sh --host <ip>
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
SCRIPTS_PATH="${ARGS[scripts-path]:-/home/sigil/SigilGate/scripts}"
SERVICE_USER="${ARGS[service-user]:-sigil}"

if [ -z "$HOST" ]; then
    echo "Использование: $0 --host <ip> [--scripts-path <path>] [--service-user <user>]"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

log_info "=== Настройка systemd-сервисов → $HOST ==="
log_info "Scripts path  : $SCRIPTS_PATH"
log_info "Service user  : $SERVICE_USER"

# Генерация и деплой unit-файлов
log_info "[1/3] Деплой unit-файлов..."

for UNIT in sigilgate-sync sigilgate-rotate; do
    # Читаем шаблон с ноды (он уже там после clone scripts)
    # Деплоим с заменёнными плейсхолдерами
    remote_sudo "$HOST" << REMOTE
sed \
    -e 's|<SERVICE_USER>|$SERVICE_USER|g' \
    -e 's|<SCRIPTS_PATH>|$SCRIPTS_PATH|g' \
    "$SCRIPTS_PATH/core/$UNIT.service" \
    > /etc/systemd/system/$UNIT.service

cp "$SCRIPTS_PATH/core/$UNIT.timer" /etc/systemd/system/$UNIT.timer
REMOTE
    log_success "  $UNIT: OK"
done

# Reload и enable
log_info "[2/3] Активация сервисов..."
remote_sudo "$HOST" << 'REMOTE'
systemctl daemon-reload
systemctl enable sigilgate-sync.timer
systemctl enable sigilgate-rotate.timer
systemctl start sigilgate-sync.timer
systemctl start sigilgate-rotate.timer
REMOTE
log_success "Таймеры активированы"

# Проверка
log_info "[3/3] Статус..."
remote_exec "$HOST" << 'REMOTE'
systemctl list-timers --no-pager | grep sigilgate || true
REMOTE

log_success "=== Сервисы Core настроены ==="
log_info "Просмотр логов:"
log_info "  journalctl -u sigilgate-sync -f"
log_info "  journalctl -u sigilgate-rotate -f"
