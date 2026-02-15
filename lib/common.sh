#!/bin/bash
#
# common.sh
# Общая библиотека скриптов автоматизации Sigil Gate
#
# Подключение:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"
#

# --- Определение корня репозитория scripts ---

if [ -z "${SIGIL_BASE_DIR:-}" ]; then
    SIGIL_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# --- Загрузка окружения ---

load_env() {
    local env_file="$SIGIL_BASE_DIR/.env"
    if [ -f "$env_file" ]; then
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            if [ -z "${!key:-}" ]; then
                export "$key=$value"
            fi
        done < "$env_file"
    fi
}

require_env() {
    local var_name="$1"
    if [ -z "${!var_name:-}" ]; then
        log_error "Переменная окружения $var_name не задана"
        exit 1
    fi
}

# --- Логирование ---

_log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

log_info()    { _log "INFO" "$@"; }
log_error()   { _log "ERROR" "$@" >&2; }
log_success() { _log "OK" "$@"; }

# --- Утилиты ---

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        log_error "Нет доступного генератора UUID (uuidgen или /proc/sys/kernel/random/uuid)"
        exit 1
    fi
}

store_read() {
    local dir="$1"
    local file="$2"
    local path="$SIGIL_STORE_PATH/$dir/$file"
    if [ ! -f "$path" ]; then
        log_error "Файл не найден: $dir/$file"
        return 1
    fi
    cat "$path"
}

# --- SSH ---

remote_exec() {
    local host="$1"
    shift
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        -i "$SIGIL_SSH_KEY" \
        "$SIGIL_SSH_USER@$host" \
        "$@"
}

remote_sudo() {
    local host="$1"
    shift
    remote_exec "$host" "echo '$SIGIL_SSH_PASSWORD' | sudo -S bash -s" "$@"
}

# --- Разбор аргументов ---

parse_args() {
    declare -gA ARGS
    while [ $# -gt 0 ]; do
        case "$1" in
            --*)
                local key="${1#--}"
                if [ $# -lt 2 ] || [[ "$2" == --* ]]; then
                    ARGS["$key"]="true"
                    shift
                else
                    ARGS["$key"]="$2"
                    shift 2
                fi
                ;;
            *)
                log_error "Неизвестный аргумент: $1"
                exit 1
                ;;
        esac
    done
}
