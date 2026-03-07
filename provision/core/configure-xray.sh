#!/bin/bash
#
# provision/core/configure-xray.sh
# Настройка Xray на Core-ноде
#
# Core принимает VLESS+gRPC от Entry-нод (через Nginx) и маршрутизирует
# трафик в интернет (Freedom). Клиентская запись (UUID) — это туннельный
# идентификатор, которым Entry аутентифицируется на Core.
#
# Использование:
#   ./provision/core/configure-xray.sh \
#     --host <ip> \
#     --grpc-path <path> \
#     --uuid <uuid>
#
# Пример:
#   ./provision/core/configure-xray.sh \
#     --host 128.22.161.34 \
#     --grpc-path api.v2.rpc.a1b2c3d4e5f6a7b8 \
#     --uuid $(uuidgen | tr '[:upper:]' '[:lower:]')
#
# Переменные окружения:
#   SIGIL_SSH_KEY, SIGIL_SSH_USER, SIGIL_SSH_PASSWORD
#   SIGIL_CORE_XRAY_PORT (внутренний порт, по умолчанию: 10004)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"
GRPC_PATH="${ARGS[grpc-path]:-}"
UUID="${ARGS[uuid]:-}"
XRAY_PORT="${SIGIL_CORE_XRAY_PORT:-10004}"

if [ -z "$HOST" ] || [ -z "$GRPC_PATH" ] || [ -z "$UUID" ]; then
    echo "Использование: $0 --host <ip> --grpc-path <path> --uuid <uuid>"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

log_info "=== Настройка Xray (Core) → $HOST ==="
log_info "gRPC path: $GRPC_PATH"
log_info "UUID     : $UUID"
log_info "Порт     : $XRAY_PORT (внутренний)"

# Бэкап существующего конфига
log_info "[1/3] Резервная копия конфига..."
remote_sudo "$HOST" << 'REMOTE'
[ -f /usr/local/etc/xray/config.json ] \
    && cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak \
    || true
REMOTE

# Создание конфига
log_info "[2/3] Создание конфига Xray..."
remote_sudo "$HOST" << REMOTE
cat > /usr/local/etc/xray/config.json << 'XRAY'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-grpc-entry",
      "listen": "127.0.0.1",
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "level": 0, "email": "tunnel" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "$GRPC_PATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "inboundTag": ["vless-grpc-entry"],
        "outboundTag": "direct"
      }
    ]
  }
}
XRAY

/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
REMOTE
log_success "Конфиг создан и прошёл валидацию"

# Перезапуск
log_info "[3/3] Перезапуск Xray..."
remote_sudo "$HOST" << 'REMOTE'
systemctl enable xray
systemctl restart xray
sleep 2
REMOTE

STATUS=$(remote_exec "$HOST" "sudo systemctl is-active xray")
log_success "Xray: $STATUS"
log_info "UUID туннеля: $UUID (использовать в configure-xray.sh Entry-нод)"
