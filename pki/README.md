# pki/ — Управление SSH CA

Скрипты для работы с SSH-инфраструктурой ключей **Sigil Gate**: выпуск и отзыв сертификатов, деплой доверия на ноды.

## Архитектура

Двухуровневая иерархия:

- **Root CA** — хранится на Root-ноде в `PKI_SSH_DIR`. Выпускает host-сертификаты для Core-нод и user-сертификаты для `sigil`.
- **Core CA** — отдельная ключевая пара на каждую Core-ноду. Подписывает host-сертификаты Entry-нод своей группы. Приватный ключ хранится на Root-ноде и деплоится на Core.

## Переменные окружения

| Переменная | Описание | По умолчанию |
|------------|----------|-------------|
| `PKI_SSH_DIR` | Директория PKI на Root-ноде | `/root/SigilGate/pki/ssh` |
| `SIGIL_SSH_KEY` | SSH-ключ для подключения к нодам | — |
| `SIGIL_SSH_USER` | Пользователь на нодах | — |
| `SIGIL_SSH_PASSWORD` | sudo-пароль | — |

## Структура PKI_SSH_DIR

```
/root/SigilGate/pki/ssh/
├── root_ca              # приватный ключ Root CA
├── root_ca.pub          # публичный ключ Root CA
├── revoked_keys         # отозванные ключи (KRL-формат)
├── <id>-ca              # приватный ключ Core CA (по одному на Core)
├── <id>-ca.pub          # публичный ключ Core CA
└── issued/              # копии выпущенных сертификатов
    ├── core-1-host-cert.pub
    └── sigil@<ip>-user-cert.pub
```

## Скрипты

| Скрипт | Назначение | Где запускать |
|--------|-----------|--------------|
| `ca-init.sh` | Инициализация Root CA | Root-нода, один раз |
| `deploy-ca-trust.sh` | Деплой CA trust на ноду | Root-нода |
| `issue-host-cert.sh` | Выпуск host-сертификата | Root-нода |
| `issue-user-cert.sh` | Выпуск user-сертификата для sigil | Root-нода |
| `issue-core-ca.sh` | Выпуск Core CA, деплой на Core-ноду | Root-нода |
| `revoke-cert.sh` | Отзыв ключа/сертификата | Root-нода |

## Порядок настройки новой ноды

```bash
# 1. Инициализировать Root CA (один раз)
./pki/ca-init.sh

# 2. Задеплоить CA trust (TrustedUserCAKeys, RevokedKeys, @cert-authority)
./pki/deploy-ca-trust.sh --host <ip>

# 3. Выпустить host-сертификат для ноды
./pki/issue-host-cert.sh \
  --host <ip> \
  --identity <node-id> \
  --principals <hostname>,<ip> \
  --validity +6m          # Core: +6m, Entry: +1m

# 4. Выпустить user-сертификат для sigil
./pki/issue-user-cert.sh --host <ip> --validity +6m

# Для Core-ноды дополнительно:
# 5. Выпустить Core CA (для подписи Entry-нод этой Core)
./pki/issue-core-ca.sh --host <core-ip> --identity <core-id>

# 6. Задеплоить Core CA pub key на все ноды
./pki/deploy-ca-trust.sh --host <any-node-ip> --core-ca /root/SigilGate/pki/ssh/<core-id>-ca.pub
```
