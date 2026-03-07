#!/bin/bash
#
# provision/common/probe.sh
# Диагностика ноды: сбор системной информации
#
# Подключается через начального пользователя (ubuntu/root) с паролем
# и собирает данные, необходимые для внесения в registry.
#
# Использование:
#   ./provision/common/probe.sh --host <ip> --init-user <user> --init-password <pass>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../lib/provision.sh"

parse_args "$@"

HOST="${ARGS[host]:-}"
INIT_USER="${ARGS[init-user]:-${INIT_USER:-ubuntu}}"
INIT_PASS="${ARGS[init-password]:-${INIT_PASS:-}}"

if [ -z "$HOST" ] || [ -z "$INIT_PASS" ]; then
    echo "Использование: $0 --host <ip> [--init-user ubuntu] --init-password <pass>"
    exit 1
fi

require_init_env

log_info "=== Диагностика ноды: $HOST ==="

init_exec_script "$HOST" << 'REMOTE'
echo "=== OS ==="
. /etc/os-release && echo "$PRETTY_NAME"

echo "=== Hostname ==="
hostname

echo "=== CPU ==="
lscpu | grep -E "^(Model name|CPU\(s\)|Architecture)" | sed 's/  */ /g'

echo "=== RAM ==="
free -m | awk '/^Mem:/ {printf "Total: %d MB\n", $2}'

echo "=== Disk ==="
df -h / | awk 'NR==2 {printf "Total: %s, Used: %s, Free: %s\n", $2, $3, $4}'

echo "=== IP ==="
ip -4 addr show | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | grep -v '^127' | head -1

echo "=== Kernel ==="
uname -r
REMOTE
