#!/bin/bash
#
# provision/core/setup-tls.sh
# Получение TLS-сертификата Let's Encrypt через Certbot
#
# ТРЕБОВАНИЕ: A-запись домена должна указывать на IP ноды
# и порты 80/443 должны быть открыты до запуска этого скрипта.
#
# Использование:
#   ./provision/core/setup-tls.sh --host <ip> --domain <domain>
#
# Пример:
#   ./provision/core/setup-tls.sh --host 128.22.161.34 --domain newcore.example.com
#
# Переменные окружения:
#   SIGIL_SSH_KEY, SIGIL_SSH_USER, SIGIL_SSH_PASSWORD
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"
DOMAIN="${ARGS[domain]:-}"

if [ -z "$HOST" ] || [ -z "$DOMAIN" ]; then
    echo "Использование: $0 --host <ip> --domain <domain>"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

log_info "=== Получение TLS-сертификата → $HOST ==="
log_info "Домен: $DOMAIN"
log_info "ВНИМАНИЕ: A-запись $DOMAIN → $HOST должна быть настроена!"

# Временный nginx конфиг для certbot (HTTP-01 challenge)
log_info "[1/3] Временный nginx конфиг для HTTP-01..."
remote_sudo "$HOST" << REMOTE
cat > /etc/nginx/sites-available/$DOMAIN << 'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root /var/www/$DOMAIN/html;
    location / { try_files \$uri \$uri/ =404; }
}
NGINX
mkdir -p /var/www/$DOMAIN/html
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
REMOTE

# Получение сертификата
log_info "[2/3] Certbot..."
remote_sudo "$HOST" << REMOTE
certbot --nginx \
    -d $DOMAIN \
    --non-interactive \
    --agree-tos \
    --email admin@$DOMAIN \
    --redirect
REMOTE

# Проверка
log_info "[3/3] Проверка сертификата..."
CERT_INFO=$(remote_exec "$HOST" "sudo openssl x509 -in /etc/letsencrypt/live/$DOMAIN/cert.pem -noout -dates 2>/dev/null")
log_success "Сертификат получен:"
log_info "$CERT_INFO"
log_success "=== TLS готов для $DOMAIN ==="
