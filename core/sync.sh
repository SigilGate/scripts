#!/bin/bash
#
# core/sync.sh [оркестратор]
# Синхронизация git-репозиториев на Core-ноде
#
# Выполняет два направления синхронизации:
#   1. registry → GitHub  (push локальных изменений)
#   2. GitHub → scripts   (pull удалённых изменений)
#
# Запускается по systemd timer (sigilgate-sync.timer) каждые 15 минут.
# Логи доступны через: journalctl -u sigilgate-sync
#
# Использование:
#   ./core/sync.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env

ERRORS=0

log_info "=== Синхронизация репозиториев ==="

# --- [1/2] registry → GitHub ---

log_info "[1/2] registry → GitHub (push)..."
if ! "$SCRIPT_DIR/../store/push.sh"; then
    log_error "registry: ошибка синхронизации"
    ERRORS=$((ERRORS + 1))
fi

# --- [2/2] GitHub → scripts ---

log_info "[2/2] GitHub → scripts (pull)..."
if ! "$SCRIPT_DIR/pull-scripts.sh"; then
    log_error "scripts: ошибка синхронизации"
    ERRORS=$((ERRORS + 1))
fi

# --- Итог ---

echo "" >&2
if [ "$ERRORS" -gt 0 ]; then
    log_error "=== Синхронизация завершена с ошибками: ${ERRORS} из 2 ==="
    exit 1
fi

log_success "=== Синхронизация завершена успешно ==="
