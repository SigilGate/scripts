# trial/ — Управление триал-подключениями

Скрипты для обслуживания бесплатных пробных подключений к сети.

## Принцип работы

Каждое триал-подключение создаётся как устройство сервисного пользователя `trial` (ID 3).

**Именование устройства:** `<telegram_id><цифра_лимита>`

Последний символ имени — однозначное число от 0 до 9, означающее количество оставшихся подключений **после текущего использования**:

| Имя устройства | telegram_id | Лимит после этого использования |
|----------------|-------------|----------------------------------|
| `1234569`      | `123456`    | 9 (первое из 10 использований)   |
| `1234568`      | `123456`    | 8                                |
| `1234560`      | `123456`    | 0 (последнее, 10-е использование)|

При следующем запросе после `1234560` выдаётся сообщение об исчерпании лимита.

## Жизненный цикл триал-устройства

```
Создано → active (в Xray на Entry-ноде, ссылка выдана пользователю)
           ↓ (через 1 час: cleanup.sh или ленивая проверка бота)
        inactive (снято с Entry-ноды)
           ↓ (expire.sh)
        archived (хранится для учёта лимита)
           ↓ (prune.sh, при наличии более новых записей)
        удалено (кроме записи с минимальным лимитом)
```

## Скрипты

### find.sh — поиск триал-устройств `[утилита]`

```bash
./trial/find.sh --telegram-id <id> [--status active|inactive|archived]
```

Возвращает JSON-массив `[{uuid, device, status, created}]` для заданного `telegram_id`.
Без `--status` возвращает устройства с любым статусом.

### expire.sh — истечение одного устройства `[оркестратор]`

```bash
./trial/expire.sh --uuid <uuid>
```

Снимает устройство с Entry-нод и переводит в `archived`.
Вызывает: `devices/deactivate.sh` → `devices/update.sh --status archived`

### prune.sh — прореживание архивных записей `[оркестратор]`

```bash
./trial/prune.sh --telegram-id <id>
```

Из всех `archived`-устройств данного `telegram_id` оставляет только запись с
наименьшей цифрой лимита (максимальный расход), остальные удаляет.

### cleanup.sh — плановая очистка `[оркестратор]`

```bash
./trial/cleanup.sh [--max-age <секунды>]   # по умолчанию 3600
```

Запускается по расписанию (systemd timer, раз в час).

1. Истекает все `active`-устройства пользователя `trial`, чей файл старше `max-age` секунд.
2. Прореживает архивные записи для каждого `telegram_id`.

## Переменные окружения

| Переменная           | По умолчанию | Описание                          |
|----------------------|--------------|-----------------------------------|
| `SIGIL_STORE_PATH`   | —            | Путь к хранилищу (обязательная)   |
| `SIGIL_TRIAL_USER_ID`| `3`          | ID сервисного пользователя trial  |

## Настройка systemd timer (на Core-ноде)

`/etc/systemd/system/sigilgate-trial-cleanup.service`:
```ini
[Unit]
Description=Sigil Gate trial cleanup

[Service]
Type=oneshot
User=sigil
EnvironmentFile=/home/sigil/.config/sigilgate-bot.env
ExecStart=/home/sigil/scripts/trial/cleanup.sh
```

`/etc/systemd/system/sigilgate-trial-cleanup.timer`:
```ini
[Unit]
Description=Sigil Gate trial cleanup (hourly)

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
```

Активация:
```bash
sudo systemctl enable --now sigilgate-trial-cleanup.timer
```
