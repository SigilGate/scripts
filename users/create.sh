#!/bin/bash
#
# users/create.sh
# Создание записи пользователя в хранилище
#
# Использование:
#   ./users/create.sh --username "Ivan" [--core-node 202.223.48.9]
#
# Необязательные параметры:
#   --core-node <ip>               (если не задан — core_nodes: [])
#   --email user@example.com
#   --telegram @username
#   --telegram-id 123456789
#   --hash "password_hash"
#   --status active|inactive|archived  (по умолчанию: active)
#
# Выводит ID созданного пользователя в stdout
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

parse_args "$@"

USERNAME="${ARGS[username]:-}"
CORE_NODE="${ARGS[core-node]:-}"

if [ -z "$USERNAME" ]; then
    log_error "Использование: $0 --username <name> [--core-node <ip>]"
    exit 1
fi

# --- Валидация необязательных полей ---

EMAIL="${ARGS[email]:-}"
TELEGRAM="${ARGS[telegram]:-}"
TELEGRAM_ID="${ARGS[telegram-id]:-}"
HASH="${ARGS[hash]:-}"
STATUS="${ARGS[status]:-active}"

if [ "$STATUS" != "active" ] && [ "$STATUS" != "inactive" ] && [ "$STATUS" != "archived" ]; then
    log_error "Статус должен быть active, inactive или archived: $STATUS"
    exit 1
fi

if [ -n "$EMAIL" ] && [[ "$EMAIL" != *@*.* ]]; then
    log_error "Некорректный email: $EMAIL"
    exit 1
fi

if [ -n "$TELEGRAM" ] && [[ "$TELEGRAM" != @* ]]; then
    log_error "Telegram должен начинаться с @: $TELEGRAM"
    exit 1
fi

if [ -n "$TELEGRAM_ID" ] && ! [[ "$TELEGRAM_ID" =~ ^[0-9]+$ ]]; then
    log_error "Telegram ID должен быть положительным целым числом: $TELEGRAM_ID"
    exit 1
fi

# --- Проверка уникальности username ---

for USER_FILE in "$SIGIL_STORE_PATH"/users/*.json; do
    [ -f "$USER_FILE" ] || continue
    EXISTING=$(jq -r '.username' "$USER_FILE")
    if [ "$EXISTING" = "$USERNAME" ]; then
        log_error "Пользователь с именем $USERNAME уже существует"
        exit 1
    fi
done

# --- Проверка уникальности telegram_id ---

if [ -n "$TELEGRAM_ID" ]; then
    for USER_FILE in "$SIGIL_STORE_PATH"/users/*.json; do
        [ -f "$USER_FILE" ] || continue
        EXISTING_TG_ID=$(jq -r '.telegram_id // empty' "$USER_FILE")
        if [ "$EXISTING_TG_ID" = "$TELEGRAM_ID" ]; then
            log_error "Пользователь с Telegram ID $TELEGRAM_ID уже существует"
            exit 1
        fi
    done
fi

# --- Проверка Core-ноды (если указана) ---

if [ -n "$CORE_NODE" ]; then
    NODE_JSON=$(store_read "nodes" "${CORE_NODE}.json") || {
        log_error "Нода $CORE_NODE не найдена в хранилище"
        exit 1
    }

    NODE_STATUS=$(echo "$NODE_JSON" | jq -r '.status')
    if [ "$NODE_STATUS" != "active" ]; then
        log_error "Нода $CORE_NODE не активна (статус: $NODE_STATUS)"
        exit 1
    fi

    ROLE_FILE="$SIGIL_STORE_PATH/roles/core_${CORE_NODE}.json"
    if [ ! -f "$ROLE_FILE" ]; then
        log_error "Нода $CORE_NODE не имеет роли core"
        exit 1
    fi

    ROLE_STATUS=$(jq -r '.status' "$ROLE_FILE")
    if [ "$ROLE_STATUS" != "active" ]; then
        log_error "Роль core для ноды $CORE_NODE не активна (статус: $ROLE_STATUS)"
        exit 1
    fi
fi

# --- Вычисление следующего ID ---

MAX_ID=0
for USER_FILE in "$SIGIL_STORE_PATH"/users/*.json; do
    [ -f "$USER_FILE" ] || continue
    FILE_ID=$(basename "$USER_FILE" .json)
    if [ "$FILE_ID" -gt "$MAX_ID" ] 2>/dev/null; then
        MAX_ID="$FILE_ID"
    fi
done

NEW_ID=$((MAX_ID + 1))

# --- Создание записи ---

USER_PATH="$SIGIL_STORE_PATH/users/${NEW_ID}.json"
CREATED=$(date '+%Y-%m-%d')

jq -n \
    --argjson id "$NEW_ID" \
    --arg username "$USERNAME" \
    --arg status "$STATUS" \
    --arg email "$EMAIL" \
    --arg telegram "$TELEGRAM" \
    --arg telegram_id "$TELEGRAM_ID" \
    --arg hash "$HASH" \
    --arg core_node "$CORE_NODE" \
    --arg created "$CREATED" \
    '{
        id: $id,
        username: $username,
        status: $status,
        hash: (if $hash == "" then null else $hash end),
        email: (if $email == "" then null else $email end),
        telegram: (if $telegram == "" then null else $telegram end),
        telegram_id: (if $telegram_id == "" then null else ($telegram_id | tonumber) end),
        core_nodes: (if $core_node == "" then [] else [$core_node] end),
        created: $created
    }' > "$USER_PATH"

log_info "Пользователь создан: $USERNAME (ID: $NEW_ID)" >&2
if [ -n "$CORE_NODE" ]; then
    log_info "Core-нода: $CORE_NODE" >&2
fi

# Вывод ID для использования в цепочке
echo "$NEW_ID"
