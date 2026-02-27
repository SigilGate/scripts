# core/ — операции на Core-ноде

Скрипты и конфиги для операций, выполняемых непосредственно на Core-ноде как периодические задачи.

## Файлы

| Файл | Назначение |
|------|------------|
| `sync.sh` | Оркестратор синхронизации репозиториев (каждые 15 минут) |
| `pull-scripts.sh` | Pull обновлений репозитория scripts с GitHub |
| `sigilgate-sync.service` | systemd-сервис для синхронизации (шаблон) |
| `sigilgate-sync.timer` | systemd-таймер (каждые 15 минут, шаблон) |
| `rotate-path.sh` | Скрипт ротации gRPC serviceName |
| `sigilgate-rotate.service` | systemd-сервис для ротации (шаблон) |
| `sigilgate-rotate.timer` | systemd-таймер для ротации (шаблон) |

## sync.sh [оркестратор]

Запускает два скрипта синхронизации последовательно. Оба выполняются независимо: ошибка одного не прерывает второй.

**Что делает:**
1. Вызывает `store/push.sh` — отправляет локальные изменения registry на GitHub.
2. Вызывает `core/pull-scripts.sh` — подтягивает обновления репозитория scripts с GitHub.

Завершается с exit 1, если хотя бы один из этапов завершился с ошибкой. Статус и детали фиксируются в systemd journal.

**Запуск вручную:**
```bash
./core/sync.sh
```

**Логи:**
```bash
journalctl -u sigilgate-sync -f
```

---

## pull-scripts.sh [атомарный]

Подтягивает обновления репозитория `scripts` с GitHub на Core-ноду.

На Core репозиторий `scripts` используется только для чтения: все изменения вносятся в удалённый репозиторий через стандартный рабочий процесс, отсюда они подтягиваются на ноду. Локальные коммиты в этом репозитории — нештатная ситуация.

**Переменные окружения:**

| Переменная | Обязательная | Описание |
|------------|-------------|----------|
| `SIGIL_SCRIPTS_PATH` | да | Путь к локальному клону репозитория scripts |

**Логика:**

| Состояние | Действие |
|-----------|----------|
| remote == local | exit 0 (актуально) |
| только remote впереди | `git pull --rebase` → exit 0 |
| local содержит локальные коммиты | exit 1 (нештатная ситуация, требуется ручная проверка) |
| pull --rebase не удался | `rebase --abort` → exit 1 |

**Запуск вручную:**
```bash
./core/pull-scripts.sh
```

---

## Развёртывание синхронизации (sigilgate-sync)

### Требования

- Клон репозитория `scripts` на Core-ноде (`SIGIL_SCRIPTS_PATH`)
- Клон репозитория `registry` на Core-ноде (`SIGIL_STORE_PATH`)
- SSH-доступ к GitHub по ключу (или HTTPS с токеном в remote URL)
- `git` на Core-ноде
- Сервисный пользователь с правом записи в оба репозитория

### 1. Создать `.env`

```bash
cat >> <SCRIPTS_PATH>/.env << 'EOF'
SIGIL_SCRIPTS_PATH=<SCRIPTS_REPO_PATH>
EOF
```

### 2. Установить systemd-юниты

```bash
# Заменить <SERVICE_USER> и <SCRIPTS_PATH> реальными значениями
sed -e 's|<SERVICE_USER>|sigil|g' \
    -e 's|<SCRIPTS_PATH>|/home/sigil/SigilGate/scripts|g' \
    core/sigilgate-sync.service \
    | sudo tee /etc/systemd/system/sigilgate-sync.service

sudo cp core/sigilgate-sync.timer /etc/systemd/system/sigilgate-sync.timer

sudo systemctl daemon-reload
sudo systemctl enable --now sigilgate-sync.timer
```

### 3. Проверить

```bash
# Тестовый запуск
sudo systemctl start sigilgate-sync.service

# Логи
journalctl -u sigilgate-sync -f

# Статус таймера
systemctl list-timers sigilgate-sync.timer
```

---

## rotate-path.sh

Периодически меняет `serviceName` на внутреннем канале Entry → Core, затрудняя статистический анализ трафика. Запускается по systemd timer.

**Что делает:**
1. Генерирует новый случайный `serviceName` формата `api.v2.rpc.<16 hex>`.
2. Обновляет конфиги Nginx и Xray на Core-ноде, перезагружает сервисы.
3. По SSH обновляет **только outbound** `serviceName` в Xray на каждой Entry-ноде.
4. Обновляет `core_service_name` и `last_rotation` в registry, коммитит изменения.

**Что не затрагивается:** клиентский inbound на Entry (Nginx + Xray inbound) — клиентские подключения продолжают работать без изменений.

**Запуск вручную:**
```bash
./core/rotate-path.sh
```

**Переменные окружения:**

| Переменная | Обязательная | Описание |
|------------|-------------|----------|
| `SIGIL_STORE_PATH` | да | Путь к локальному клону registry |
| `SIGIL_SSH_KEY` | да | SSH-ключ для подключения к Entry-нодам |
| `SIGIL_SSH_USER` | да | Пользователь на Entry-нодах |
| `SIGIL_SSH_PASSWORD` | да | sudo-пароль (локально и на Entry) |
| `SIGIL_CORE_IP` | нет | IP этой Core-ноды (фильтр маршрутов; если не задан — все активные) |
| `SIGIL_CORE_XRAY_CONF` | нет | Путь к Xray-конфигу Core (по умолчанию: `/usr/local/etc/xray/config.json`) |
| `SIGIL_CORE_NGINX_DIR` | нет | Директория Nginx sites-enabled (по умолчанию: `/etc/nginx/sites-enabled`) |
| `SIGIL_ENTRY_XRAY_CONF` | нет | Путь к Xray-конфигу Entry (по умолчанию: `/usr/local/etc/xray/config.json`) |

## Развёртывание

### Требования

- Клон репозитория `scripts` на Core-ноде
- Клон репозитория `registry` на Core-ноде (`SIGIL_STORE_PATH`)
- SSH-доступ к Entry-нодам по ключу
- `jq`, `openssl` на Core-ноде
- Сервисный пользователь с правами sudo

### 1. Создать `.env`

```bash
cat > <SCRIPTS_PATH>/.env << 'EOF'
SIGIL_STORE_PATH=<REGISTRY_PATH>
SIGIL_SSH_KEY=<SSH_KEY_PATH>
SIGIL_SSH_USER=<SSH_USER>
SIGIL_SSH_PASSWORD=<SSH_PASSWORD>
SIGIL_CORE_IP=<CORE_IP>
EOF
```

### 2. Установить systemd-юниты

Скопировать шаблоны, подставив значения вместо плейсхолдеров:

```bash
# Заменить <SERVICE_USER> и <SCRIPTS_PATH> реальными значениями
sed -e 's|<SERVICE_USER>|sigil|g' \
    -e 's|<SCRIPTS_PATH>|/home/sigil/SigilGate/scripts|g' \
    core/sigilgate-rotate.service \
    | sudo tee /etc/systemd/system/sigilgate-rotate.service

sudo cp core/sigilgate-rotate.timer /etc/systemd/system/sigilgate-rotate.timer

sudo systemctl daemon-reload
sudo systemctl enable --now sigilgate-rotate.timer
```

### 3. Проверить

```bash
# Тестовый запуск
sudo systemctl start sigilgate-rotate.service

# Логи
journalctl -u sigilgate-rotate -f

# Статус таймера
systemctl list-timers sigilgate-rotate.timer
```

## Конфигурация нод

Скрипт работает с конфигами Nginx и Xray на Core и Entry-нодах. Ниже — минимальные фрагменты, необходимые для работы ротации.

### Core — Nginx

gRPC-трафик от Entry маршрутизируется по `serviceName`:

```nginx
server {
    listen 443 ssl http2;
    server_name <CORE_DOMAIN>;

    # ... TLS-настройки ...

    location /<SERVICE_NAME> {
        grpc_pass grpc://127.0.0.1:<XRAY_PORT>;
    }
}
```

`<SERVICE_NAME>` соответствует `serviceName` в Xray-конфиге. Скрипт обновляет этот `location` при каждой ротации.

### Core — Xray (фрагмент inbound)

```json
{
  "inbounds": [{
    "protocol": "vless",
    "settings": { "clients": [ ... ] },
    "streamSettings": {
      "network": "grpc",
      "grpcSettings": {
        "serviceName": "<SERVICE_NAME>"
      }
    }
  }]
}
```

### Entry — Xray (фрагмент outbound)

Скрипт обновляет **только** этот блок. Inbound Entry не затрагивается.

```json
{
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "<CORE_DOMAIN>",
        "port": 443,
        "users": [{ "id": "<UUID>", "encryption": "none" }]
      }]
    },
    "streamSettings": {
      "network": "grpc",
      "grpcSettings": {
        "serviceName": "<SERVICE_NAME>"
      }
    }
  }]
}
```

`<SERVICE_NAME>` в outbound Entry должен совпадать с `<SERVICE_NAME>` в inbound Core.
