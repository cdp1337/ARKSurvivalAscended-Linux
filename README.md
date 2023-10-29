# Tools for managing ARK Survival Ascended on Linux

## What does it do?

This script will:

* Download Proton from Glorious Eggroll's build
* Install Steam and SteamCMD
* Create a `steam` user for running the game server
* Install ARK Survival Ascended Dedicated Server using standard Steam procedures
* Setup a systemd service for running the game server

---

What this script will _not_ do:

Provide any sort of management interface over your server. 
It's just a bootstrap script to install the game and its dependencies in a standard way
so _you_ can choose how you want to manage it.

## Features

Because it's managed with systemd, standardized commands are used for managing the server.
This includes an auto-restart for the game server if it crashes and auto-update on restarts.

By default, the game server will **automatically start at boot**!

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

### Start, Stop, Restart

Start your server:

```bash
sudo systemctl start ark-island
```

---

Restarting your server (and updating):

_The service will automatically check Steam for the newest version of the game on restart._

```bash
sudo systemctl restart ark-island
```

---

Stopping your server:

```bash
sudo systemctl stop ark-island
```

---


### Configuring the game ini

Configuration of your server via the configuration ini is available in `/home/steam/island-UserGameSettings.ini`

```bash
sudo -u steam nano /etc/steam/island-UserGameSettings.ini
```

_Sssshhh, I use `vim` too, but `nano` is easier for most newcomers._


### Adding command line arguments

Some arguments for the game server need to be passed in as CLI arguments.

```bash
sudo nano /etc/systemd/system/ark-island.service
```

And look at the line

```
ExecStart=/home/steam/(wherever-steam-is)/compatibilitytools.d/GE-Proton8-21/proton run ArkAscendedServer.exe TheIsland_WP?listen
```

Command line arguments can just be added to the end.  When done editing, reload the system config:

(This DOES NOT restart the game server)

```bash
sudo systemctl daemon-reload
```