# Tools for installing ARK Survival Ascended Dedicated Server on Linux

## What does it do?

This script will:

* Download Proton from Glorious Eggroll's build
* Install Steam and SteamCMD
* Create a `steam` user for running the game server
* Install ARK Survival Ascended Dedicated Server using standard Steam procedures
* Setup a systemd service for running the game server
* Add firewall service for game server (with firewalld)

---

What this script will _not_ do:

Provide any sort of management interface over your server. 
It's just a bootstrap script to install the game and its dependencies in a standard way
so _you_ can choose how you want to manage it.

## Features

Because it's managed with systemd, standardized commands are used for managing the server.
This includes an auto-restart for the game server if it crashes.

By default, the game server will **automatically start at boot**!

A start and stop script is included in `/home/steam/ArkSurvivalAscended`
for starting and stopping all maps, (not to mention updating before they start).

Sets up multiple maps on a single install, and **all of them can run at the same time**
(providing your server has the horsepower to do so).

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

On installation, you have the option of selecting which map to enable.
All maps are installed so they can be disabled / enabled at any time.

* Island - `ark-island`
* Aberration - `ark-aberration`
* Club ARK - `ark-club`
* Scorched - `ark-scorched`
* The Center - `ark-thecenter`

### Start, Stop, Restart

Start a single map:

```bash
# Start the Island
sudo systemctl start ark-island

# Start Aberration
sudo systemctl start ark-aberration

# Start Club ARK
sudo systemctl start ark-club

# Start Scorched
sudo systemctl start ark-scorched

# Start the center
sudo systemctl start ark-thecenter
```

---

Restarting a single map:

```bash
# Restart the Island
sudo systemctl restart ark-island

# Restart Aberration
sudo systemctl restart ark-aberration

# Restart Club ARK
sudo systemctl restart ark-club

# Restart Scorched
sudo systemctl restart ark-scorched

# Restart the center
sudo systemctl restart ark-thecenter
```

---

Stopping a single map:

```bash
# Stop the Island
sudo systemctl stop ark-island

# Stop Aberration
sudo systemctl stop ark-aberration

# Stop Club ARK
sudo systemctl stop ark-club

# Stop Scorched
sudo systemctl stop ark-scorched

# Stop the center
sudo systemctl stop ark-thecenter
```

---

Start all maps (and update game server from Steam):

```bash
/home/steam/ArkSurvivalAscended/start_all.sh
```

---

Stop all maps:

```bash
/home/steam/ArkSurvivalAscended/stop_all.sh
```

---

### Enable and disable maps

```bash
# Enable Island
sudo systemctl enable ark-island

# Enable Aberration
sudo systemctl enable ark-aberration

# Enable Club ARK
sudo systemctl enable ark-club

# Enable Scorched
sudo systemctl enable ark-scorched

# Enable The Center
sudo systemctl enable ark-thecenter
```

Enabling a map will set it to start at boot, but it **will not** start the map immediately.
use `sudo systemctl start ...` to start the requested map manually.

---

```bash
# Disable Island
sudo systemctl disable ark-island

# Disable Aberration
sudo systemctl disable ark-aberration

# Disable Club ARK
sudo systemctl disable ark-club

# Disable Scorched
sudo systemctl disable ark-scorched

# Disable The Center
sudo systemctl disable ark-thecenter
```

Disabling a map will prevent it from starting at boot, but it **will not** stop the map.
use `sudo systemctl stop ...` to stop the requested map manually.

---


### Configuring the game ini

Configuration of your server via the configuration ini is available in `/home/steam/ArkSurvivalAscended/GameUserSettings.ini`

```bash
sudo -u steam nano /home/steam/ArkSurvivalAscended/GameUserSettings.ini
```

_Sssshhh, I use `vim` too, but `nano` is easier for most newcomers._


### Adding command line arguments

Some arguments for the game server need to be passed in as CLI arguments.

```bash
# Configure start parameters for the Island
sudo nano /home/steam/ArkSurvivalAscended/services/ark-island.conf

# Configure start parameters for Aberration
sudo nano /home/steam/ArkSurvivalAscended/services/ark-aberration.conf

# Configure start parameters for Club ARK
sudo nano /home/steam/ArkSurvivalAscended/services/ark-club.conf

# Configure start parameters for Scorched
sudo nano /home/steam/ArkSurvivalAscended/services/ark-scorched.conf

# Configure start parameters for The Center
sudo nano /home/steam/ArkSurvivalAscended/services/ark-thecenter.conf
```

When done editing, reload the system config:

(This DOES NOT restart the game server)

```bash
sudo systemctl daemon-reload
```

### Automatic restarts

Want to restart your server automatically at 5a each morning?

Edit crontab `sudo nano /etc/crontab` and add:

```bash
0 5 * * * root /home/steam/ArkSurvivalAscended/stop_all.sh && /home/steam/ArkSurvivalAscended/start_all.sh
```

(0 is minute, 5 is hour in 24-hour notation, followed by '* * *' for every day, every month, every weekday)
