#!/bin/bash
#
# nodes/list-core.sh
# Список активных Core-нод
#
# Использование:
#   ./nodes/list-core.sh
#
# Возвращает JSON-массив: [{ip, hostname, location}]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
load_env
require_env SIGIL_STORE_PATH

RESULT="[]"

for ROLE_FILE in "$SIGIL_STORE_PATH"/roles/core_*.json; do
    [ -f "$ROLE_FILE" ] || continue

    ROLE_STATUS=$(jq -r '.status' "$ROLE_FILE")
    [ "$ROLE_STATUS" != "active" ] && continue

    NODE_IP=$(jq -r '.node_ip' "$ROLE_FILE")
    NODE_FILE="$SIGIL_STORE_PATH/nodes/${NODE_IP}.json"
    [ -f "$NODE_FILE" ] || continue

    NODE_STATUS=$(jq -r '.status' "$NODE_FILE")
    [ "$NODE_STATUS" != "active" ] && continue

    ENTRY=$(jq -n \
        --arg ip "$NODE_IP" \
        --arg hostname "$(jq -r '.hostname' "$NODE_FILE")" \
        --arg location "$(jq -r '.location' "$NODE_FILE")" \
        '{ip: $ip, hostname: $hostname, location: $location}')

    RESULT=$(echo "$RESULT" | jq --argjson entry "$ENTRY" '. += [$entry]')
done

echo "$RESULT"
