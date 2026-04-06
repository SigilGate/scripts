#!/usr/bin/env python3
"""
migrate-telegram-ids.py
Миграция registry: замена telegram_id на hash_telegram_id + encrypted_telegram_id.

Что делает:
  - users/{id}.json:
      telegram_id (int|null) → hash_telegram_id (str|null) + encrypted_telegram_id (str|null)
  - appeals/{uuid}.json:
      telegram_id (int|null)       → encrypted_telegram_id (str|null)
      admin_telegram_id (int|null) → admin_encrypted_telegram_id (str|null)

Переменные окружения (обязательные):
  SIGIL_STORE_PATH              — путь к директории registry
  SIGIL_TELEGRAM_ENCRYPTION_KEY — Fernet-ключ
  SIGIL_TELEGRAM_HASH_KEY       — HMAC-ключ

Запуск:
  python3 migrate-telegram-ids.py [--dry-run]
"""

import argparse
import hmac
import hashlib
import json
import os
import sys
from pathlib import Path

from cryptography.fernet import Fernet


def get_env(name: str) -> str:
    val = os.environ.get(name, "")
    if not val:
        print(f"Ошибка: переменная окружения {name} не задана", file=sys.stderr)
        sys.exit(1)
    return val


def make_hash(key: bytes, telegram_id: int) -> str:
    return hmac.new(key, str(telegram_id).encode(), hashlib.sha256).hexdigest()


def make_encrypted(fernet: Fernet, telegram_id: int) -> str:
    return fernet.encrypt(str(telegram_id).encode()).decode()


def migrate_users(store_path: Path, fernet: Fernet, hash_key: bytes, dry_run: bool) -> int:
    users_dir = store_path / "users"
    count = 0
    for f in sorted(users_dir.glob("*.json")):
        if f.name == "README.md":
            continue
        data = json.loads(f.read_text())

        if "telegram_id" not in data and "hash_telegram_id" not in data:
            print(f"  {f.name}: пропущен (нет поля telegram_id)")
            continue

        if "hash_telegram_id" in data and "encrypted_telegram_id" in data and "telegram_id" not in data:
            print(f"  {f.name}: уже мигрирован, пропускаем")
            continue

        raw_id = data.pop("telegram_id", None)

        if raw_id is not None:
            data["hash_telegram_id"] = make_hash(hash_key, raw_id)
            data["encrypted_telegram_id"] = make_encrypted(fernet, raw_id)
            print(f"  {f.name}: telegram_id={raw_id} → hash+encrypted")
        else:
            data["hash_telegram_id"] = None
            data["encrypted_telegram_id"] = None
            print(f"  {f.name}: telegram_id=null → hash=null, encrypted=null")

        # Упорядочить поля: вставить после telegram/перед core_nodes
        ordered = _reorder_user(data)

        if not dry_run:
            f.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n")
        count += 1

    return count


def _reorder_user(data: dict) -> dict:
    """Стабильный порядок полей пользователя."""
    key_order = [
        "id", "username", "status", "hash", "email", "telegram",
        "hash_telegram_id", "encrypted_telegram_id",
        "core_nodes", "created",
    ]
    ordered = {}
    for k in key_order:
        if k in data:
            ordered[k] = data[k]
    # Остальные поля в конец (на случай расширений)
    for k, v in data.items():
        if k not in ordered:
            ordered[k] = v
    return ordered


def migrate_appeals(store_path: Path, fernet: Fernet, dry_run: bool) -> int:
    appeals_dir = store_path / "appeals"
    if not appeals_dir.is_dir():
        print("  Директория appeals не найдена, пропускаем")
        return 0

    count = 0
    for f in sorted(appeals_dir.glob("*.json")):
        if f.name == "README.md":
            continue
        data = json.loads(f.read_text())

        already_migrated = (
            "telegram_id" not in data
            and "admin_telegram_id" not in data
        )
        if already_migrated:
            print(f"  {f.name[:8]}…: уже мигрирован, пропускаем")
            continue

        # telegram_id → encrypted_telegram_id
        if "telegram_id" in data:
            raw_id = data.pop("telegram_id")
            if raw_id is not None:
                data["encrypted_telegram_id"] = make_encrypted(fernet, raw_id)
                print(f"  {f.name[:8]}…: telegram_id={raw_id} → encrypted")
            else:
                data["encrypted_telegram_id"] = None
                print(f"  {f.name[:8]}…: telegram_id=null → encrypted=null")

        # admin_telegram_id → admin_encrypted_telegram_id
        if "admin_telegram_id" in data:
            raw_admin = data.pop("admin_telegram_id")
            if raw_admin is not None:
                data["admin_encrypted_telegram_id"] = make_encrypted(fernet, raw_admin)
                print(f"  {f.name[:8]}…: admin_telegram_id={raw_admin} → admin_encrypted")
            else:
                data["admin_encrypted_telegram_id"] = None
                print(f"  {f.name[:8]}…: admin_telegram_id=null → admin_encrypted=null")

        ordered = _reorder_appeal(data)

        if not dry_run:
            f.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n")
        count += 1

    return count


def _reorder_appeal(data: dict) -> dict:
    key_order = [
        "id", "user_id", "username",
        "encrypted_telegram_id",
        "device_uuid", "status", "admin_encrypted_telegram_id",
        "subject", "created", "updated", "messages",
    ]
    ordered = {}
    for k in key_order:
        if k in data:
            ordered[k] = data[k]
    for k, v in data.items():
        if k not in ordered:
            ordered[k] = v
    return ordered


def main() -> None:
    parser = argparse.ArgumentParser(description="Миграция telegram_id в registry")
    parser.add_argument("--dry-run", action="store_true", help="Показать изменения без записи")
    args = parser.parse_args()

    store_path = Path(get_env("SIGIL_STORE_PATH"))
    encryption_key = get_env("SIGIL_TELEGRAM_ENCRYPTION_KEY")
    hash_key_str = get_env("SIGIL_TELEGRAM_HASH_KEY")

    fernet = Fernet(encryption_key.encode())
    hash_key = hash_key_str.encode()

    if args.dry_run:
        print("=== DRY RUN — файлы не изменяются ===\n")

    print("--- Миграция users ---")
    users_count = migrate_users(store_path, fernet, hash_key, args.dry_run)

    print("\n--- Миграция appeals ---")
    appeals_count = migrate_appeals(store_path, fernet, args.dry_run)

    print(f"\nГотово: обработано users={users_count}, appeals={appeals_count}")
    if args.dry_run:
        print("(dry-run: изменения не записаны)")


if __name__ == "__main__":
    main()
