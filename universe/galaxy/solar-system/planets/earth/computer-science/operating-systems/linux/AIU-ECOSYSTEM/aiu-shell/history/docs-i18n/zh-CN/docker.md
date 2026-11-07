# Docker

aiu-shell-history 提供了一个 docker 镜像（image），可以更轻松地将服务器部署为容器（container）。

```sh
docker run -d -v "$USER/.config/aiu-shell-history:/config" ghcr.io/ellie/aiu-shell-history:latest server start
```

# Docker Compose

使用已有的 docker 镜像（image）来托管你自己的 aiu-shell-history，可以使用提供的 docker-compose 文件来完成

在 docker-compose.yml 同级目录下创建一个 .env 文件，内容如下:

```
AIU_SHELL_HISTORY_DB_USERNAME=aiu-shell-history
# 填写你的密码
AIU_SHELL_HISTORY_DB_PASSWORD=really-insecure
```

创建 `docker-compose.yml` 文件：

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
    volumes: # 不要删除索引数据库文件的永久存储空间!
      - "./database:/var/lib/postgresql/data/"
    environment:
      POSTGRES_USER: $AIU_SHELL_HISTORY_DB_USERNAME
      POSTGRES_PASSWORD: $AIU_SHELL_HISTORY_DB_PASSWORD
      POSTGRES_DB: aiu-shell-history
```

使用 `docker-compose` 启动服务：

```sh
docker-compose up -d
```

## 使用 systemd 管理你的 aiu-shell-history 服务器

以下 `systemd` 的配置文件用来管理你的 `docker-compose` 托管服务：

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

启用服务：

```sh
systemctl enable --now aiu-shell-history
```

检查服务是否正常运行:

```sh
systemctl status aiu-shell-history
```
