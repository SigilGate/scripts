#!/bin/bash
#
# core/pull-scripts.sh
# Получение обновлений репозитория scripts с GitHub
#
# Запускается автоматически из core/sync.sh каждые 15 минут.
# На Core-ноде репозиторий scripts используется только для чтения:
# все изменения вносятся в удалённый репозиторий, отсюда они
# подтягиваются на Core. Локальные коммиты в этом репозитории
# являются нештатной ситуацией.
#
# Использование:
#   ./core/pull-scripts.sh
#
# Переменные окружения (обязательные):
#   SIGIL_SCRIPTS_PATH  — путь к локальному клону репозитория scripts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env

require_env SIGIL_SCRIPTS_PATH

BRANCH="main"

# --- Получить актуальное состояние remote ---

log_info "Scripts: получение состояния remote..."
git -C "$SIGIL_SCRIPTS_PATH" fetch origin

REMOTE_AHEAD=$(git -C "$SIGIL_SCRIPTS_PATH" rev-list "HEAD..origin/${BRANCH}" --count)
LOCAL_AHEAD=$(git -C "$SIGIL_SCRIPTS_PATH" rev-list "origin/${BRANCH}..HEAD" --count)

# --- Локальный клон актуален ---

if [ "$REMOTE_AHEAD" -eq 0 ]; then
    log_info "Scripts: локальный клон актуален, pull не нужен"
    exit 0
fi

# --- Неожиданные локальные коммиты --- нештатная ситуация ---

if [ "$LOCAL_AHEAD" -gt 0 ]; then
    log_error "Scripts: обнаружены локальные коммиты (+${LOCAL_AHEAD}), которых нет в remote"
    log_error "Scripts: нештатная ситуация — pull прерван, требуется ручная проверка"
    exit 1
fi

# --- Только remote впереди — обычный pull ---

log_info "Scripts: remote опережает на ${REMOTE_AHEAD} коммит(ов), pull..."

if git -C "$SIGIL_SCRIPTS_PATH" pull --rebase origin "$BRANCH"; then
    log_success "Scripts: подтянуто ${REMOTE_AHEAD} коммит(ов)"
    exit 0
fi

# --- Pull не удался ---

git -C "$SIGIL_SCRIPTS_PATH" rebase --abort 2>/dev/null || true
log_error "Scripts: pull --rebase завершился с ошибкой. Требуется ручная проверка."
exit 1
