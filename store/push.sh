#!/bin/bash
#
# store/push.sh
# Отправка локальных изменений registry на GitHub
#
# Запускается автоматически из core/sync.sh каждые 15 минут.
# При расхождении ветвей выполняет git pull --rebase.
# При конфликте rebase сохраняет отчёт в logs/ и применяет
# force push (Core wins): локальные изменения побеждают,
# факт и детали конфликта фиксируются в репозитории.
#
# Использование:
#   ./store/push.sh
#
# Переменные окружения (обязательные):
#   SIGIL_STORE_PATH  — путь к локальному клону registry
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env

require_env SIGIL_STORE_PATH

BRANCH="main"

# --- Получить актуальное состояние remote ---

log_info "Registry: получение состояния remote..."
git -C "$SIGIL_STORE_PATH" fetch origin

LOCAL_AHEAD=$(git -C "$SIGIL_STORE_PATH" rev-list "origin/${BRANCH}..HEAD" --count)
REMOTE_AHEAD=$(git -C "$SIGIL_STORE_PATH" rev-list "HEAD..origin/${BRANCH}" --count)

# --- Нет локальных изменений ---

if [ "$LOCAL_AHEAD" -eq 0 ]; then
    log_info "Registry: нет локальных изменений, push не нужен"
    exit 0
fi

# --- Только local впереди — обычный push ---

if [ "$REMOTE_AHEAD" -eq 0 ]; then
    log_info "Registry: local опережает remote на ${LOCAL_AHEAD} коммит(ов), push..."
    git -C "$SIGIL_STORE_PATH" push origin "$BRANCH"
    log_success "Registry: запушено ${LOCAL_AHEAD} коммит(ов)"
    exit 0
fi

# --- Расхождение — попытка rebase ---

log_info "Registry: расхождение (local: +${LOCAL_AHEAD}, remote: +${REMOTE_AHEAD}), попытка rebase..."

if git -C "$SIGIL_STORE_PATH" pull --rebase origin "$BRANCH" 2>&1; then
    git -C "$SIGIL_STORE_PATH" push origin "$BRANCH"
    log_success "Registry: rebase успешен, запушено"
    exit 0
fi

# --- Rebase не удался — фиксируем конфликт и применяем Core wins ---

log_error "Registry: rebase завершился с ошибкой, применяем стратегию Core wins"
git -C "$SIGIL_STORE_PATH" rebase --abort 2>/dev/null || true

TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
CONFLICT_BASENAME="sync-conflict-${TIMESTAMP//:/}"

LOCAL_SHA=$(git -C "$SIGIL_STORE_PATH" rev-parse HEAD)
REMOTE_SHA=$(git -C "$SIGIL_STORE_PATH" rev-parse "origin/${BRANCH}")

LOCAL_LOG=$(git -C "$SIGIL_STORE_PATH" log --oneline "origin/${BRANCH}..HEAD" 2>/dev/null \
    || echo "(не удалось получить)")
REMOTE_LOG=$(git -C "$SIGIL_STORE_PATH" log --oneline "HEAD..origin/${BRANCH}" 2>/dev/null \
    || echo "(не удалось получить)")
CHANGED_FILES=$(git -C "$SIGIL_STORE_PATH" diff --name-only "HEAD...origin/${BRANCH}" 2>/dev/null \
    || echo "(не удалось определить)")

LOGS_DIR="$SIGIL_STORE_PATH/logs"
mkdir -p "$LOGS_DIR"
CONFLICT_FILE="$LOGS_DIR/${CONFLICT_BASENAME}.md"

cat > "$CONFLICT_FILE" << EOF
# Конфликт синхронизации registry

**Время:** ${TIMESTAMP}
**Локальный HEAD:** \`${LOCAL_SHA}\` (+${LOCAL_AHEAD} коммитов)
**Remote HEAD:** \`${REMOTE_SHA}\` (+${REMOTE_AHEAD} коммитов)

## Расхождение

### Локальные коммиты (не в remote)

\`\`\`
${LOCAL_LOG}
\`\`\`

### Remote-коммиты (не в local)

\`\`\`
${REMOTE_LOG}
\`\`\`

## Файлы с расхождениями

\`\`\`
${CHANGED_FILES}
\`\`\`

## Действие

Rebase не удался. Локальные изменения применены принудительно (Core wins).
Remote-изменения потеряны. Требуется ручная проверка.
EOF

git -C "$SIGIL_STORE_PATH" add "$CONFLICT_FILE"
git -C "$SIGIL_STORE_PATH" \
    -c user.name="Sigil Gate Team AI Assistant" \
    -c user.email="git@sigilgate" \
    commit -m "log: sync conflict ${TIMESTAMP}"

git -C "$SIGIL_STORE_PATH" push --force-with-lease origin "$BRANCH"

log_error "Registry: конфликт зафиксирован — logs/${CONFLICT_BASENAME}.md"
exit 1
