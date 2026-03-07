#!/bin/bash
#
# provision/core/setup-repos.sh
# Клонирование репозиториев scripts и registry на Core-ноду
#
# Создаёт структуру /home/sigil/SigilGate/ с клонами репозиториев
# и файл .env с переменными окружения для скриптов.
#
# Использование:
#   ./provision/core/setup-repos.sh \
#     --host <ip> \
#     --github-pat <token>
#
# Переменные окружения:
#   SIGIL_SSH_KEY, SIGIL_SSH_USER, SIGIL_SSH_PASSWORD
#   GITHUB_PAT (альтернатива --github-pat)
#
# Структура на Core:
#   /home/sigil/SigilGate/
#   ├── scripts/    # публичный репозиторий (read-only pull)
#   ├── registry/   # приватный репозиторий (push + pull)
#   └── scripts/.env
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
load_env

parse_args "$@"

HOST="${ARGS[host]:-}"
GITHUB_PAT="${ARGS[github-pat]:-${GITHUB_PAT:-}}"

if [ -z "$HOST" ] || [ -z "$GITHUB_PAT" ]; then
    echo "Использование: $0 --host <ip> --github-pat <token>"
    echo "Или задайте переменную GITHUB_PAT"
    exit 1
fi

require_env SIGIL_SSH_KEY
require_env SIGIL_SSH_USER
require_env SIGIL_SSH_PASSWORD

SIGIL_PASSWORD="${SIGIL_SSH_PASSWORD}"
BASE_DIR="/home/sigil/SigilGate"
SCRIPTS_URL="https://github.com/SigilGate/scripts.git"
REGISTRY_URL="https://${GITHUB_PAT}@github.com/SigilGate/registry.git"

log_info "=== Настройка репозиториев → $HOST ==="
log_info "Базовая директория: $BASE_DIR"

# Создаём структуру директорий
log_info "[1/4] Создание директорий..."
remote_exec "$HOST" "mkdir -p $BASE_DIR"

# Клон scripts (публичный)
log_info "[2/4] Клон scripts..."
remote_exec "$HOST" << REMOTE
if [ -d "$BASE_DIR/scripts/.git" ]; then
    echo "scripts уже клонирован, пропуск"
else
    git clone $SCRIPTS_URL $BASE_DIR/scripts
fi
REMOTE
log_success "scripts: OK"

# Клон registry (приватный, с PAT)
log_info "[3/4] Клон registry..."
remote_exec "$HOST" << REMOTE
if [ -d "$BASE_DIR/registry/.git" ]; then
    echo "registry уже клонирован, пропуск"
else
    git clone "$REGISTRY_URL" $BASE_DIR/registry
    # Убираем PAT из remote URL после клонирования
    git -C $BASE_DIR/registry remote set-url origin https://github.com/SigilGate/registry.git
fi
REMOTE
# Сохраняем PAT отдельно в .gitconfig для дальнейших операций
remote_exec "$HOST" "git config --global credential.helper store"
remote_exec "$HOST" "echo 'https://x-access-token:$GITHUB_PAT@github.com' > ~/.git-credentials && chmod 600 ~/.git-credentials"
log_success "registry: OK"

# Создаём .env
log_info "[4/4] Создание .env..."
remote_exec "$HOST" << REMOTE
cat > $BASE_DIR/scripts/.env << 'ENV'
SIGIL_STORE_PATH=$BASE_DIR/registry
SIGIL_SCRIPTS_PATH=$BASE_DIR/scripts
SIGIL_SSH_KEY=/home/sigil/.ssh/id_ed25519
SIGIL_SSH_USER=sigil
SIGIL_SSH_PASSWORD=$SIGIL_PASSWORD
ENV
chmod 600 $BASE_DIR/scripts/.env
REMOTE
log_success ".env создан: $BASE_DIR/scripts/.env"

log_success "=== Репозитории настроены ==="
log_info "scripts  : $BASE_DIR/scripts"
log_info "registry : $BASE_DIR/registry"
log_info ".env     : $BASE_DIR/scripts/.env"
