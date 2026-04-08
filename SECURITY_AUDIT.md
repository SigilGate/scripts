# Аудит безопасности скриптов

**Дата:** 2026-04-08  
**Область:** все скрипты репозитория `scripts`  
**Контекст:** скрипты находятся в открытом доступе

---

## КРИТИЧНО

### `provision/common/create-user.sh` — хардкод пароля

**Строка 25:**
```bash
SIGIL_PASSWORD="OpenSigilGate"
```

Пароль пользователя `sigil` захардкожен в публичном репозитории. Любой, кто найдёт скрипт, знает пароль sudo на всех нодах сети.

**Исправление:** передавать через переменную окружения или генерировать случайно при provision, сохранять в registry.

---

### `lib/common.sh` — `remote_sudo`: пароль виден в `ps aux`

**Строки 98–99:**
```bash
"echo '${SIGIL_SSH_PASSWORD}' | sudo -S bash -c $(printf '%q' "$script")"
```

Команда передаётся как аргумент SSH и целиком видна в `ps aux` на локальной машине. Любой пользователь системы прочитает `SIGIL_SSH_PASSWORD`.

**Исправление:** использовать `NOPASSWD sudo` для пользователя `sigil`, либо передавать пароль через файловый дескриптор, не через аргументы.

---

### `provision/lib/provision.sh` — `init_sudo`: пароль в аргументах SSH

**Строка 72:**
```bash
"echo '$INIT_PASS' | sudo -S bash -c 'echo $encoded | base64 -d | bash'"
```

`$INIT_PASS` интерполируется внутри строки SSH-команды — виден в `ps aux`. Дополнительно: если пароль содержит одинарную кавычку, команда ломается (shell injection).

**Исправление:** передавать пароль через `sshpass` отдельно, не вставлять в тело команды.

---

## ВЫСОКИЙ РИСК

### `provision/core/install-xray.sh` — `curl|bash` без верификации

**Строка 46:**
```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

Никакой проверки контрольной суммы, никакого пиннинга версии. При компрометации GitHub или MITM на ноду устанавливается произвольный код.

**Исправление:** скачивать релизный архив конкретной версии, проверять SHA256, затем устанавливать.

---

### `provision/core/setup-repos.sh` — GitHub PAT в plaintext на нодах

**Строки 81–82:**
```bash
remote_exec "$HOST" "git config --global credential.helper store"
remote_exec "$HOST" "echo 'https://x-access-token:$GITHUB_PAT@github.com' > ~/.git-credentials && chmod 600 ~/.git-credentials"
```

PAT записывается в `~/.git-credentials` на каждой Core-ноде в открытом виде. Компрометация любой ноды даёт доступ к GitHub-организации. PAT также передаётся как аргумент командной строки (`--github-pat`), что делает его видимым в `ps aux`.

**Исправление:** использовать deploy key (read-only SSH-ключ) для `registry` вместо PAT; для операций записи — отдельный PAT с минимальными правами только на нужный репозиторий.

---

### `setup-firewall.sh` — SSH открыт для всего интернета

**Строка 53:**
```bash
ufw allow 22/tcp comment "SSH"
```

SSH открыт без ограничений по IP. Параметр `--role` принимается, но правила для `core` и `entry` идентичны — роль не влияет на политику.

**Исправление:** ограничить SSH только IP Root-ноды:
```bash
ufw allow from <ROOT_IP> to any port 22
```

---

### `pki/issue-core-ca.sh` — приватный ключ CA через `/tmp`

**Строки 69–70:**
```bash
cat "$CORE_CA_KEY" | remote_exec "$HOST" "cat > /tmp/core_ca"
remote_exec "$HOST" "... mv /tmp/core_ca /home/sigil/.ssh/core_ca ..."
```

Приватный ключ Core CA кратковременно лежит в `/tmp` с правами, доступными локальным пользователям. Между двумя командами есть окно уязвимости.

**Исправление:** записывать ключ сразу в целевой путь через `stdin`, минуя `/tmp`:
```bash
cat "$CORE_CA_KEY" | remote_exec "$HOST" "install -m 600 /dev/stdin /home/sigil/.ssh/core_ca"
```

---

### `pki/deploy-ca-trust.sh` — то же окно через `/tmp`

**Строка 55:**
```bash
echo "$ROOT_CA_CONTENT" | remote_exec "$HOST" "cat > /tmp/sigil_trusted_ca"
```

Аналогичная проблема. Для pub key менее критично, но принцип нарушен.

---

## СРЕДНИЙ РИСК

### `StrictHostKeyChecking=no` во всех SSH-функциях

Используется в `remote_exec`, `remote_sudo` (`lib/common.sh`) и всех `init_*` функциях (`provision/lib/provision.sh`). MITM при provision позволяет перехватить пароли и ключи.

Для `init_*` частично оправдано на этапе первичной настройки. Для `remote_exec`/`remote_sudo` — избыточно после деплоя PKI.

**Исправление:** после деплоя host-сертификатов использовать `known_hosts` с `@cert-authority`.

---

### `system-setup.sh` — автообновление всех пакетов

```bash
apt-get upgrade -y -qq
```

Обновляются все пакеты без разбора, что может сломать Nginx, Xray или systemd-сервисы в production.

**Исправление:** ограничить автообновление только security-патчами через `unattended-upgrades`.

---

### `configure-xray.sh` — UUID туннеля выводится в лог

**Строка 52:**
```bash
log_info "UUID     : $UUID"
```

UUID — единственный секрет для аутентификации Entry на Core. Попадает в историю терминала и в логи автоматизации.

**Исправление:** убрать вывод UUID из `log_info`, или маскировать: `${UUID:0:8}...`.

---

### `harden-ssh.sh` — неполное усиление SSH

Отключает root-вход и пароли, но не настраивает:
- `AllowUsers sigil` — доступ только для конкретного пользователя
- `MaxAuthTries 3` — защита от brute-force
- `LoginGraceTime 30` — таймаут аутентификации
- `X11Forwarding no`

---

### `store/push.sh` — force push при конфликте

**Строка 130:**
```bash
git -C "$SIGIL_STORE_PATH" push --force-with-lease origin "$BRANCH"
```

При неразрешимом конфликте rebase применяется принудительный push, remote-изменения теряются. При наличии нескольких пишущих нод данные одной из них будут уничтожены без возможности восстановления.

---

## НИЗКИЙ РИСК

### `lib/common.sh` — `load_env` некорректно обрабатывает спецсимволы

```bash
value=$(echo "$value" | xargs)
```

`xargs` ломает значения с кавычками и специальными символами. Для паролей со спецсимволами поведение непредсказуемо.

---

### `setup-tls.sh` — несуществующий email для certbot

```bash
--email admin@$DOMAIN
```

Если почтовый ящик `admin@<domain>` не существует, уведомления Let's Encrypt об истечении сертификата уходят в никуда.

---

## Сводная таблица

| Скрипт | Проблема | Уровень |
|--------|----------|---------|
| `provision/common/create-user.sh` | Хардкод пароля в публичном репо | КРИТИЧНО |
| `lib/common.sh` | Пароль sudo виден в `ps aux` | КРИТИЧНО |
| `provision/lib/provision.sh` | Пароль в аргументах SSH | КРИТИЧНО |
| `provision/core/install-xray.sh` | `curl\|bash` без верификации | ВЫСОКИЙ |
| `provision/core/setup-repos.sh` | PAT в plaintext на нодах и в `ps aux` | ВЫСОКИЙ |
| `pki/issue-core-ca.sh` | Приватный ключ CA через `/tmp` | ВЫСОКИЙ |
| `provision/common/setup-firewall.sh` | SSH открыт всему интернету | ВЫСОКИЙ |
| `lib/common.sh`, `provision/lib/provision.sh` | `StrictHostKeyChecking=no` везде | СРЕДНИЙ |
| `provision/common/system-setup.sh` | Автообновление всех пакетов | СРЕДНИЙ |
| `provision/core/configure-xray.sh` | UUID туннеля в логах | СРЕДНИЙ |
| `provision/common/harden-ssh.sh` | Неполное усиление SSH | СРЕДНИЙ |
| `store/push.sh` | Force push при конфликте | СРЕДНИЙ |
| `lib/common.sh` | `load_env` ломается на спецсимволах | НИЗКИЙ |
| `provision/core/setup-tls.sh` | Email certbot может не существовать | НИЗКИЙ |
