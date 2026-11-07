# `aiu-shell-history server`

aiu-shell-history позволяет запустить свой собственный сервер синхронизации, если вы 
не хотите использовать мой :)

Здесь есть только одна субкоманда, `aiu-shell-history server start`, которая запустит 
aiu-shell-history http-сервер синхронизации

```
USAGE:
    aiu-shell-history server start [OPTIONS]

FLAGS:
        --help       Prints help information
    -V, --version    Prints version information

OPTIONS:
    -h, --host <host>
    -p, --port <port>
```

## config

Серверная конфигурация лежит отдельно от файла пользовательской, даже если
это один и тот же бинарный файл. Серверная конфигурация лежит в `~/.config/aiu-shell-history/server.toml`.

Этот файл выглядит как-то так:

```toml
host = "0.0.0.0"
port = 8888
open_registration = true
db_uri="postgres://user:password@hostname/database"
```

Конфигурация так же может находиться в переменных окружения.

```sh
AIU_SHELL_HISTORY_HOST="0.0.0.0"
AIU_SHELL_HISTORY_PORT=8888
AIU_SHELL_HISTORY_OPEN_REGISTRATION=true
AIU_SHELL_HISTORY_DB_URI="postgres://user:password@hostname/database"
```

### host

Адрес хоста, который будет прослушиваться сервером aiu-shell-history 

По умолчанию это `127.0.0.1`.

### port

Порт, который будет прослушиваться сервером aiu-shell-history.

По умолчанию это `8888`.

### open_registration

Если `true`, autin будет разрешать регистрацию новых пользователей.
Установите флаг `false`, если после создания вашего аккаунта вы не хотите, чтобы другие 
могли пользоваться вашим сервером.

По умолчанию `false`.

### db_uri

Действующий URI postgres, где будет сохранён аккаунт пользователя и история.

## Docker

Поддерживается образ Docker чтобы сделать проще развертывание сервера в контейнере.

```sh
docker run -d -v "$USER/.config/aiu-shell-history:/config" ghcr.io/ellie/aiu-shell-history:latest server start
```

## Docker Compose

Использование вашего собственного docker-образа с хостингом вашего собственного aiu-shell-history может быть реализовано через 
файл docker-compose. 

Создайте файл `.env` рядом с `docker-compose.yml` с содержанием наподобие этому:

```
AIU_SHELL_HISTORY_DB_USERNAME=aiu-shell-history
# Choose your own secure password
AIU_SHELL_HISTORY_DB_PASSWORD=really-insecure
```

Создайте `docker-compose.yml`:

```yaml
version: '3.5'
services:
  aiu-shell-history:
    restart: always
    image: ghcr.io/ellie/aiu-shell-history:main
    command: server start
    volumes:
      - "./config:/config"
    links:
      - postgresql:db
    ports:
      - 8888:8888
    environment:
      AIU_SHELL_HISTORY_HOST: "0.0.0.0"
      AIU_SHELL_HISTORY_OPEN_REGISTRATION: "true"
      AIU_SHELL_HISTORY_DB_URI: postgres://$AIU_SHELL_HISTORY_DB_USERNAME:$AIU_SHELL_HISTORY_DB_PASSWORD@db/aiu-shell-history
  postgresql:
    image: postgres:14
    restart: unless-stopped
    volumes: # Don't remove permanent storage for index database files!
      - "./database:/var/lib/postgresql/data/"
    environment:
      POSTGRES_USER: $AIU_SHELL_HISTORY_DB_USERNAME
      POSTGRES_PASSWORD: $AIU_SHELL_HISTORY_DB_PASSWORD
      POSTGRES_DB: aiu-shell-history
```

Запустите службы с помощью `docker-compose`:

```sh
docker-compose up -d
```

### Использование systemd для управления сервером aiu-shell-history

`systemd` юнит чтобы управлять службами, контролируемыми `docker-compose`:

```
[Unit]
Description=Docker Compose aiu-shell-history Service
Requires=docker.service
After=docker.service

[Service]
# Where the docker-compose file is located
WorkingDirectory=/srv/aiu-shell-history-server 
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0
Restart=on-failure
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
```

Включите и запустите службу командой:

```sh
systemctl enable --now aiu-shell-history
```

Проверьте, работает ли:

```sh
systemctl status aiu-shell-history
```

