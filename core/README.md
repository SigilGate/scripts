# core/ — операции на Core-ноде

Скрипты, выполняемые непосредственно на Core-ноде как периодические задачи.

## Скрипты

| Скрипт | Тип | Назначение |
|--------|-----|------------|
| `rotate-path.sh` | автономный | Ротация gRPC serviceName на участке Entry → Core |

## rotate-path.sh

Периодически меняет `serviceName` на внутреннем канале Entry → Core, затрудняя статистический анализ трафика. Запускается по systemd timer.

**Что делает:**
1. Генерирует новый случайный `serviceName` формата `api.v2.rpc.<16 hex>`.
2. Обновляет конфиги Nginx и Xray на Core-ноде, перезагружает сервисы.
3. По SSH обновляет **только outbound** `serviceName` в Xray на каждой Entry-ноде.
4. Обновляет `core_service_name` и `last_rotation` в registry, коммитит изменения.

**Что не затрагивается:** клиентский inbound на Entry (Nginx + Xray inbound) — клиентские подключения продолжают работать без изменений.

**Запуск:**
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
