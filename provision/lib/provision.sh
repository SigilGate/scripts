#!/bin/bash
#
# provision/lib/provision.sh
# SSH-хелперы для начального подключения к ноде
#
# Используется на этапе provision до настройки пользователя sigil и SSH-ключа.
# Подключается через начального пользователя (например, ubuntu или root) с паролем.
#
# Ожидает в окружении:
#   INIT_USER — начальный пользователь (ubuntu, root и т.п.)
#   INIT_PASS — пароль начального пользователя
#   HOST      — IP-адрес целевой ноды
#
# Подключение:
#   source "$SCRIPT_DIR/../lib/provision.sh"
#

require_init_env() {
    if [ -z "${INIT_USER:-}" ]; then
        log_error "INIT_USER не задан"
        exit 1
    fi
    if [ -z "${INIT_PASS:-}" ]; then
        log_error "INIT_PASS не задан"
        exit 1
    fi
    if ! command -v sshpass &>/dev/null; then
        log_error "sshpass не установлен: apt install sshpass"
        exit 1
    fi
}

# Выполнить команду на ноде через начального пользователя
init_exec() {
    local host="$1"; shift
    sshpass -p "$INIT_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=yes \
        -o BatchMode=no \
        -o ConnectTimeout=15 \
        "$INIT_USER@$host" "$@"
}

# Выполнить скрипт (heredoc stdin) на ноде через начального пользователя
init_exec_script() {
    local host="$1"
    local script
    script=$(cat)
    sshpass -p "$INIT_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=yes \
        -o BatchMode=no \
        -o ConnectTimeout=15 \
        "$INIT_USER@$host" bash -s <<< "$script"
}

# Выполнить скрипт с sudo
# Скрипт передаётся через base64 чтобы не конфликтовать с stdin sudo -S.
# Работает как с NOPASSWD sudo, так и с sudo требующим пароль.
init_sudo() {
    local host="$1"
    local script
    script=$(cat)
    local encoded
    encoded=$(printf '%s' "$script" | base64 | tr -d '\n')
    sshpass -p "$INIT_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=yes \
        -o BatchMode=no \
        -o ConnectTimeout=15 \
        "$INIT_USER@$host" \
        "echo '$INIT_PASS' | sudo -S bash -c 'echo $encoded | base64 -d | bash'"
}

# Скопировать файл на ноду через начального пользователя
init_scp() {
    local host="$1"
    local src="$2"
    local dst="$3"
    sshpass -p "$INIT_PASS" scp \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=yes \
        -o BatchMode=no \
        "$src" "$INIT_USER@$host:$dst"
}

# Проверить доступность ноды
init_check() {
    local host="$1"
    init_exec "$host" "echo OK" 2>/dev/null | grep -q "OK"
}
