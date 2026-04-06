#!/bin/bash
#
# lib/crypto.sh
# Утилиты шифрования и хеширования Telegram ID.
# Подключается через: source "$SCRIPT_DIR/../lib/crypto.sh"
#
# Переменные окружения:
#   SIGIL_TELEGRAM_ENCRYPTION_KEY — Fernet-ключ (base64url, 44 символа)
#   SIGIL_TELEGRAM_HASH_KEY       — HMAC-ключ (произвольная строка, рекомендуется 32+ символа)
#
# Зависимости: python3, пакет cryptography (pip install cryptography)
#

# encrypt_telegram_id <telegram_id>
# Выводит Fernet-токен в stdout. Завершается с кодом 1 при ошибке.
encrypt_telegram_id() {
    local tg_id="$1"
    python3 - "$tg_id" <<'PYEOF'
import sys, os
from cryptography.fernet import Fernet
key = os.environ.get("SIGIL_TELEGRAM_ENCRYPTION_KEY", "")
if not key:
    print("SIGIL_TELEGRAM_ENCRYPTION_KEY не задан", file=sys.stderr)
    sys.exit(1)
tg_id = sys.argv[1]
print(Fernet(key.encode()).encrypt(tg_id.encode()).decode())
PYEOF
}

# hash_telegram_id <telegram_id>
# Выводит HMAC-SHA256 hex-строку (64 символа) в stdout.
hash_telegram_id() {
    local tg_id="$1"
    python3 - "$tg_id" <<'PYEOF'
import sys, os, hmac, hashlib
key = os.environ.get("SIGIL_TELEGRAM_HASH_KEY", "")
if not key:
    print("SIGIL_TELEGRAM_HASH_KEY не задан", file=sys.stderr)
    sys.exit(1)
tg_id = sys.argv[1]
print(hmac.new(key.encode(), tg_id.encode(), hashlib.sha256).hexdigest())
PYEOF
}
