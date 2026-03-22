#!/bin/bash
#
# core/sync.sh [оркестратор]
# Синхронизация git-репозиториев на Core-ноде
#
# Выполняет синхронизацию:
#   1. registry → GitHub  (push локальных изменений)
#
# Шаг "GitHub → scripts" отключён: репозиторий scripts теперь ведётся
# непосредственно на Core-ноде, pull избыточен.
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

# --- [1/1] registry → GitHub ---

log_info "[1/1] registry → GitHub (push)..."
if ! "$SCRIPT_DIR/../store/push.sh"; then
    log_error "registry: ошибка синхронизации"
    ERRORS=$((ERRORS + 1))
fi

# --- Итог ---

echo "" >&2
if [ "$ERRORS" -gt 0 ]; then
    log_error "=== Синхронизация завершена с ошибками: ${ERRORS} из 1 ==="
    exit 1
fi

log_success "=== Синхронизация завершена успешно ==="
