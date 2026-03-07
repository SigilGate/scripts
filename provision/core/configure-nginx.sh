#!/bin/bash
#
# provision/core/configure-nginx.sh
# Настройка Nginx на Core-ноде
#
# Конфигурирует Nginx как TLS-терминатор + gRPC-прокси к Xray.
# Создаёт минимальную страницу-прикрытие.
#
# Использование:
#   ./provision/core/configure-nginx.sh \
#     --host <ip> \
#     --domain <domain> \
#     --grpc-path <path>
#
# Пример:
#   ./provision/core/configure-nginx.sh \
#     --host 128.22.161.34 \
#     --domain newcore.example.com \
#     --grpc-path api.v2.rpc.a1b2c3d4e5f6a7b8
#
# Переменные окружения:
#   SIGIL_SSH_KEY, SIGIL_SSH_USER, SIGIL_SSH_PASSWORD
#   SIGIL_CORE_XRAY_PORT (внутренний порт Xray, по умолчанию: 10004)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"
DOMAIN="${ARGS[domain]:-}"
GRPC_PATH="${ARGS[grpc-path]:-}"
XRAY_PORT="${SIGIL_CORE_XRAY_PORT:-10004}"

if [ -z "$HOST" ] || [ -z "$DOMAIN" ] || [ -z "$GRPC_PATH" ]; then
    echo "Использование: $0 --host <ip> --domain <domain> --grpc-path <path>"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

log_info "=== Настройка Nginx (Core) → $HOST ==="
log_info "Домен    : $DOMAIN"
log_info "gRPC path: $GRPC_PATH"
log_info "Xray port: $XRAY_PORT"

# Страница-прикрытие
log_info "[1/3] Страница-прикрытие..."
remote_sudo "$HOST" << REMOTE
mkdir -p /var/www/$DOMAIN/html
cat > /var/www/$DOMAIN/html/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Welcome</title>
<style>body{font-family:sans-serif;max-width:600px;margin:80px auto;color:#333}</style></head>
<body><h1>Welcome</h1><p>This server is up and running.</p></body>
</html>
HTML
chown -R www-data:www-data /var/www/$DOMAIN
REMOTE

# Nginx конфиг
log_info "[2/3] Конфигурация Nginx..."
remote_sudo "$HOST" << REMOTE
cat > /etc/nginx/sites-available/$DOMAIN << 'NGINX'
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # gRPC транспорт (Entry → Core)
    location /$GRPC_PATH {
        grpc_pass grpc://127.0.0.1:$XRAY_PORT;
        grpc_set_header Host \$host;
        grpc_read_timeout 300s;
        grpc_send_timeout 300s;
    }

    # Страница-прикрытие
    location / {
        root /var/www/$DOMAIN/html;
        try_files \$uri \$uri/ /index.html;
    }

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
NGINX

rm -f /etc/nginx/sites-enabled/$DOMAIN
ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
REMOTE
log_success "Nginx конфиг применён"

# Проверка
log_info "[3/3] Проверка..."
STATUS=$(remote_exec "$HOST" "systemctl is-active nginx")
log_success "Nginx: $STATUS"
