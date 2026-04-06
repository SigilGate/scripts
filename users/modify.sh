#!/bin/bash
#
# users/modify.sh
# Модификация полей записи пользователя
#
# Использование:
#   ./users/modify.sh --id <USER_ID> [--username "NewName"] [--status active|inactive|archived]
#                     [--email user@example.com] [--telegram @username]
#                     [--telegram-id 123456789] [--hash "password_hash"]
#                     [--add-core-node <IP>] [--remove-core-node <IP>]
#
# Можно передать несколько полей за один вызов.
# Пустое значение ("") сбрасывает поле в null (для email, telegram, telegram-id, hash).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/crypto.sh"
load_env
require_env SIGIL_STORE_PATH
require_env SIGIL_TELEGRAM_ENCRYPTION_KEY
require_env SIGIL_TELEGRAM_HASH_KEY

parse_args "$@"

USER_ID="${ARGS[id]:-}"

if [ -z "$USER_ID" ]; then
    log_error "Использование: $0 --id <ID> --<field> <value> [--<field> <value> ...]"
    exit 1
fi

USER_PATH="$SIGIL_STORE_PATH/users/${USER_ID}.json"

if [ ! -f "$USER_PATH" ]; then
    log_error "Пользователь $USER_ID не найден"
    exit 1
fi

USERNAME=$(jq -r '.username' "$USER_PATH")

# --- Определение полей для модификации ---

MODIFIABLE_FIELDS=(username status email telegram telegram-id hash add-core-node remove-core-node)
CHANGES=()

for FIELD in "${MODIFIABLE_FIELDS[@]}"; do
    # Проверяем, передан ли аргумент (включая пустое значение)
    if [ "${ARGS[$FIELD]+set}" = "set" ]; then
        CHANGES+=("$FIELD")
    fi
done

if [ ${#CHANGES[@]} -eq 0 ]; then
    log_error "Не указано ни одного поля для модификации"
    log_error "Допустимые поля: ${MODIFIABLE_FIELDS[*]}"
    exit 1
fi

# --- Валидация ---

for FIELD in "${CHANGES[@]}"; do
    VALUE="${ARGS[$FIELD]}"

    case "$FIELD" in
        username)
            if [ -z "$VALUE" ]; then
                log_error "Username не может быть пустым"
                exit 1
            fi
            # Проверка уникальности
            for USER_FILE in "$SIGIL_STORE_PATH"/users/*.json; do
                [ -f "$USER_FILE" ] || continue
                [ "$USER_FILE" = "$USER_PATH" ] && continue
                EXISTING=$(jq -r '.username' "$USER_FILE")
                if [ "$EXISTING" = "$VALUE" ]; then
                    log_error "Пользователь с именем $VALUE уже существует"
                    exit 1
                fi
            done
            ;;
        status)
            if [ "$VALUE" != "active" ] && [ "$VALUE" != "inactive" ] && [ "$VALUE" != "archived" ]; then
                log_error "Статус должен быть active, inactive или archived: $VALUE"
                exit 1
            fi
            ;;
        email)
            if [ -n "$VALUE" ] && [[ "$VALUE" != *@*.* ]]; then
                log_error "Некорректный email: $VALUE"
                exit 1
            fi
            ;;
        telegram)
            if [ -n "$VALUE" ] && [[ "$VALUE" != @* ]]; then
                log_error "Telegram должен начинаться с @: $VALUE"
                exit 1
            fi
            ;;
        telegram-id)
            if [ -n "$VALUE" ] && ! [[ "$VALUE" =~ ^[0-9]+$ ]]; then
                log_error "Telegram ID должен быть положительным целым числом: $VALUE"
                exit 1
            fi
            ;;
        hash)
            # Любое значение допустимо, пустое — сброс в null
            ;;
        add-core-node|remove-core-node)
            if [ -z "$VALUE" ]; then
                log_error "IP ноды не может быть пустым"
                exit 1
            fi
            ;;
    esac
done

# --- Применение изменений ---

TEMP_FILE=$(mktemp)
cp "$USER_PATH" "$TEMP_FILE"

for FIELD in "${CHANGES[@]}"; do
    VALUE="${ARGS[$FIELD]}"
    JSON_FIELD="$FIELD"

    # Маппинг имени аргумента на имя JSON-поля
    case "$FIELD" in
        telegram-id) JSON_FIELD="hash_telegram_id" ;;  # обрабатывается отдельно ниже
    esac

    case "$FIELD" in
        telegram-id)
            if [ -z "$VALUE" ]; then
                jq '.hash_telegram_id = null | .encrypted_telegram_id = null' "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            else
                NEW_HASH=$(hash_telegram_id "$VALUE")
                NEW_ENC=$(encrypt_telegram_id "$VALUE")
                jq --arg h "$NEW_HASH" --arg e "$NEW_ENC" \
                    '.hash_telegram_id = $h | .encrypted_telegram_id = $e' \
                    "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            fi
            ;;
        email|telegram|hash)
            if [ -z "$VALUE" ]; then
                jq ".${JSON_FIELD} = null" "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            else
                jq --arg val "$VALUE" ".${JSON_FIELD} = \$val" "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            fi
            ;;
        add-core-node)
            jq --arg node "$VALUE" '.core_nodes += [$node] | .core_nodes |= unique' "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            ;;
        remove-core-node)
            jq --arg node "$VALUE" '.core_nodes -= [$node]' "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            ;;
        *)
            jq --arg val "$VALUE" ".${JSON_FIELD} = \$val" "$TEMP_FILE" > "${TEMP_FILE}.new" && mv "${TEMP_FILE}.new" "$TEMP_FILE"
            ;;
    esac
done

mv "$TEMP_FILE" "$USER_PATH"

# --- Вывод результата ---

for FIELD in "${CHANGES[@]}"; do
    VALUE="${ARGS[$FIELD]}"
    DISPLAY_VALUE="${VALUE:-null}"
    log_info "Пользователь $USERNAME (ID: $USER_ID): $FIELD → $DISPLAY_VALUE" >&2
done
