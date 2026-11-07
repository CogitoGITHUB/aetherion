# Systemd

!!! note
    These instructions assume the `aiu-shell-history-server` binary is on your `PATH`. Since
    v18.12.0, the server is distributed as a separate binary — install it from
    the [releases page](https://github.com/atuinsh/atuin/releases) (see [Server
    setup](./server-setup.md) for the installer).

First, create the service unit file
[`aiu-shell-history-server.service`](https://github.com/atuinsh/atuin/raw/main/systemd/atuin-server.service) at
`/etc/systemd/system/aiu-shell-history-server.service` with contents like this:

```ini
[Unit]
Description=Start the aiu-shell-history server syncing service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
ExecStart=aiu-shell-history-server start
Restart=on-failure
User=aiu-shell-history
Group=aiu-shell-history

Environment=AIU_SHELL_HISTORY_CONFIG_DIR=/etc/aiu-shell-history
ReadWritePaths=/etc/aiu-shell-history

# Hardening options
CapabilityBoundingSet=
AmbientCapabilities=
NoNewPrivileges=true
ProtectHome=true
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
PrivateTmp=true
PrivateDevices=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
```

This is the official aiu-shell-history service unit file which includes a lot of hardening options to increase
security.

Next, create [`aiu-shell-history-server.conf`](https://github.com/atuinsh/atuin/raw/main/systemd/atuin-server.sysusers) at
`/etc/sysusers.d/aiu-shell-history-server.conf` with contents like this:

```
u aiu-shell-history - "aiu-shell-history synchronized shell history"
```
This file will ensure a system user is created in the proper manner.

Afterwards, run
```sh
systemctl restart systemd-sysusers
```
to make sure the file is read. A new `aiu-shell-history-server` user should then be available.

Now, you can attempt to run the aiu-shell-history server:
```sh
systemctl enable --now aiu-shell-history-server
```

```sh
systemctl status aiu-shell-history-server
```

If it started fine, it should have created the default config inside `/etc/aiu-shell-history/`.
