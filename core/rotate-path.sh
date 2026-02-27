#!/bin/bash
#
# core/rotate-path.sh
# Ротация gRPC serviceName на Core-ноде и связанных Entry-нодах
#
# Читает активные маршруты из SIGIL_STORE_PATH/routes/, обновляет конфиги
# Nginx и Xray на Core, затем по SSH обновляет outbound Xray на каждой Entry.
# После успешной ротации обновляет registry и делает коммит.
#
# Использование:
#   ./core/rotate-path.sh
#
# Переменные окружения (обязательные):
#   SIGIL_STORE_PATH      — путь к локальному клону registry
#   SIGIL_SSH_KEY         — SSH-ключ для подключения к Entry-нодам
#   SIGIL_SSH_USER        — пользователь на Entry-нодах
#   SIGIL_SSH_PASSWORD    — sudo-пароль (используется и локально, и на Entry)
#
# Переменные окружения (необязательные):
#   SIGIL_CORE_IP         — IP этой Core-ноды (фильтр маршрутов; если не задан — все активные)
#   SIGIL_CORE_XRAY_CONF  — путь к Xray-конфигу Core (по умолчанию: /usr/local/etc/xray/config.json)
#   SIGIL_CORE_NGINX_DIR  — директория Nginx sites-enabled (по умолчанию: /etc/nginx/sites-enabled)
#   SIGIL_ENTRY_XRAY_CONF — путь к Xray-конфигу Entry (по умолчанию: /usr/local/etc/xray/config.json)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env

require_env SIGIL_STORE_PATH
require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

CORE_XRAY_CONF="${SIGIL_CORE_XRAY_CONF:-/usr/local/etc/xray/config.json}"
CORE_NGINX_DIR="${SIGIL_CORE_NGINX_DIR:-/etc/nginx/sites-enabled}"
ENTRY_XRAY_CONF="${SIGIL_ENTRY_XRAY_CONF:-/usr/local/etc/xray/config.json}"

# --- Утилиты ---

generate_service_name() {
    echo "api.v2.rpc.$(openssl rand -hex 8)"
}

local_sudo() {
    echo "$SIGIL_SSH_PASSWORD" | sudo -S "$@" 2>/dev/null
}

# --- Обновление Core ---

update_core() {
    local new_path="$1"
    local old_path

    old_path=$(grep -oP '"serviceName"\s*:\s*"\Kapi\.v2\.rpc\.[a-f0-9]{16}' "$CORE_XRAY_CONF" | head -1 || true)

    if [ -z "$old_path" ]; then
        log_error "Core: не удалось определить текущий serviceName в $CORE_XRAY_CONF"
        return 1
    fi

    if [ "$old_path" = "$new_path" ]; then
        log_info "Core: путь не изменился, пропуск"
        return 0
    fi

    log_info "Core: замена $old_path → $new_path"

    local ts
    ts=$(date '+%Y%m%d_%H%M%S')

    # Бэкап и замена в Xray
    local_sudo cp "$CORE_XRAY_CONF" "${CORE_XRAY_CONF}.bak.${ts}"
    local_sudo sed -i "s|$old_path|$new_path|g" "$CORE_XRAY_CONF"

    # Замена в Nginx (только файлы, содержащие старый путь)
    for nginx_conf in "$CORE_NGINX_DIR"/*; do
        [ -f "$nginx_conf" ] || continue
        if grep -q "$old_path" "$nginx_conf" 2>/dev/null; then
            local_sudo cp "$nginx_conf" "${nginx_conf}.bak.${ts}"
            local_sudo sed -i "s|$old_path|$new_path|g" "$nginx_conf"
        fi
    done

    # Валидация Xray
    if ! local_sudo /usr/local/bin/xray run -test -config "$CORE_XRAY_CONF" >/dev/null 2>&1; then
        log_error "Core: валидация Xray не прошла, откат"
        local_sudo cp "${CORE_XRAY_CONF}.bak.${ts}" "$CORE_XRAY_CONF"
        for nginx_conf in "$CORE_NGINX_DIR"/*; do
            [ -f "${nginx_conf}.bak.${ts}" ] && local_sudo cp "${nginx_conf}.bak.${ts}" "$nginx_conf"
        done
        return 1
    fi

    # Валидация Nginx
    if ! local_sudo nginx -t >/dev/null 2>&1; then
        log_error "Core: валидация Nginx не прошла, откат"
        local_sudo cp "${CORE_XRAY_CONF}.bak.${ts}" "$CORE_XRAY_CONF"
        for nginx_conf in "$CORE_NGINX_DIR"/*; do
            [ -f "${nginx_conf}.bak.${ts}" ] && local_sudo cp "${nginx_conf}.bak.${ts}" "$nginx_conf"
        done
        return 1
    fi

    local_sudo systemctl reload nginx
    local_sudo systemctl restart xray
    log_success "Core: конфиги обновлены, сервисы перезагружены"
}

# --- Обновление Entry ---
# Меняется ТОЛЬКО outbound serviceName (→ Core).
# Inbound serviceName и Nginx (клиентская сторона) не затрагиваются.

update_entry() {
    local host="$1"
    local new_path="$2"

    log_info "Entry $host: начало обновления outbound"

    if ! remote_exec "$host" "echo OK" &>/dev/null; then
        log_error "Entry $host: недоступна по SSH"
        return 1
    fi

    local result
    result=$(remote_sudo "$host" <<REMOTE
set -e
XRAY_CONF="$ENTRY_XRAY_CONF"
BACKUP="\${XRAY_CONF}.bak.\$(date +%Y%m%d_%H%M%S)"
cp "\$XRAY_CONF" "\$BACKUP"

jq '(.outbounds[] | select(.streamSettings.grpcSettings) | .streamSettings.grpcSettings.serviceName) = "$new_path"' \
    "\$XRAY_CONF" > /tmp/xray_rotated.json
mv /tmp/xray_rotated.json "\$XRAY_CONF"

if ! /usr/local/bin/xray run -test -config "\$XRAY_CONF" >/dev/null 2>&1; then
    cp "\$BACKUP" "\$XRAY_CONF"
    echo "VALIDATION_FAILED"
    exit 1
fi

systemctl restart xray
echo "OK"
REMOTE
    )

    if [ "$result" != "OK" ]; then
        log_error "Entry $host: обновление не удалось ($result)"
        return 1
    fi

    log_success "Entry $host: outbound обновлён, Xray перезагружен"
}

# --- Обновление registry ---

update_registry() {
    local route_file="$1"
    local new_path="$2"
    local today
    today=$(date '+%Y-%m-%d')

    local tmp
    tmp=$(mktemp)
    jq --arg path "$new_path" --arg date "$today" \
        '.core_service_name = $path | .last_rotation = $date' \
        "$route_file" > "$tmp"
    mv "$tmp" "$route_file"
}

# --- Основной процесс ---

main() {
    log_info "=== Начало ротации gRPC-пути ==="

    local new_path
    new_path=$(generate_service_name)
    log_info "Новый путь: $new_path"

    # Обновить Core — если не удалось, Entry не трогаем
    if ! update_core "$new_path"; then
        log_error "Обновление Core не удалось, Entry-ноды не обновляются"
        exit 1
    fi

    # Найти активные маршруты в registry
    local routes_dir="$SIGIL_STORE_PATH/routes"
    local errors=0
    local updated=0

    for route_file in "$routes_dir"/*.json; do
        [ -f "$route_file" ] || continue

        local status entry_ip core_ip
        status=$(jq -r '.status' "$route_file")
        entry_ip=$(jq -r '.entry_ip' "$route_file")
        core_ip=$(jq -r '.core_ip' "$route_file")

        [ "$status" != "active" ] && continue

        # Если задан SIGIL_CORE_IP — обрабатываем только маршруты этой Core
        if [ -n "${SIGIL_CORE_IP:-}" ] && [ "$core_ip" != "$SIGIL_CORE_IP" ]; then
            continue
        fi

        if update_entry "$entry_ip" "$new_path"; then
            update_registry "$route_file" "$new_path"
            updated=$((updated + 1))
        else
            errors=$((errors + 1))
        fi
    done

    # Коммит изменений в registry
    if [ "$updated" -gt 0 ]; then
        "$SCRIPT_DIR/../store/commit.sh" --message "rotate gRPC serviceName → $new_path"
    fi

    if [ "$errors" -gt 0 ]; then
        log_error "=== Ротация завершена с ошибками: $errors Entry-нод не обновлено ==="
        exit 1
    fi

    log_success "=== Ротация завершена успешно, обновлено маршрутов: $updated ==="
}

main "$@"
