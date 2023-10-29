# Tools for managing ARK Survival Ascended on Linux

## What does it do?

This script will:

* Download Proton from Glorious Eggroll's build
* Install Steam and SteamCMD
* Create a `steam` user for running the game server
* Install ARK Survival Ascended Dedicated Server using standard Steam procedures
* Setup a systemd service for running the game server

## Features

Because it's managed with systemd, standardized commands are used for managing the server.
This includes an auto-restart for the game server if it crashes and auto-update on restarts.

## Installation on Debian 12

To install ARK Survival Ascended Dedicated Server on Debian 12,
download and run [server-install-debian12.sh](server-install-debian12.sh)
as root or sudo.

Debian 12 support tested on Digital Ocean, OVHCloud, and Proxmox.

Quick run (if you trust me, which you of course should not):

```bash
sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/cdp1337/ARKSurvivalAscended-Linux/main/server-install-debian12.sh)" root
```

## Managing your Server

Start your server:

```bash
sudo systemctl start ark-island
```

Restarting your server (and updating):

```bash
sudo systemctl restart ark-island
```

Stopping your server:

```bash
sudo systemctl stop ark-island
```

Configuration of your server via the configuration ini is available in `/home/steam/island-UserGameSettings.ini`