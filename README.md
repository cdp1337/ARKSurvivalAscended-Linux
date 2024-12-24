# Tools for installing ARK Survival Ascended Dedicated Server on Linux

## What does it do?

This script will:

* Download Proton from Glorious Eggroll's build
* Install Steam and SteamCMD
* Create a `steam` user for running the game server
* Install ARK Survival Ascended Dedicated Server using standard Steam procedures
* Setup a systemd service for running the game server
* Add firewall service for game server (with firewalld or UFW)
* Setup NFS shares for multi-server environments

---

What this script will _not_ do:

Provide any sort of management interface over your server.
It's just a bootstrap script to install the game and its dependencies in a standard way
so _you_ can choose how you want to manage it.

## Features

Because it's managed with systemd, standardized commands are used for managing the server.
This includes an auto-restart for the game server if it crashes.

By default, enabled game maps will **automatically start at boot**!

A start and stop script is included in `/home/steam/ArkSurvivalAscended`
for starting and stopping all maps, (not to mention updating before they start).

Sets up multiple maps on a single install, and **all of them can run at the same time**
(providing your server has the horsepower to do so).

If your single server cannot run all maps, this script supports multiple servers
sharing the same `cluster` directory via NFS to allow players to jump between maps,
even if they are on different physical servers.

## Directory Structure

```
/home/steam/ArkSurvivalAscended
├── AppFiles/                  # Game Server Files (directly managed from Steam)
├── prefixes/                  # Proton prefix directory (emulates windows filesystem)
│   ├── ark-aberration/
│   ├── ark-club/
│   ├── ark-island/
│   ├── ark-scorched/
│   ├── ark-thecenter/
│   └── ark-extinction/
├── services/                  # Service file overrides (for setting startup options)
│   ├── ark-aberration.conf
│   ├── ark-club.conf
│   ├── ark-island.conf
│   ├── ark-scorched.conf
│   ├── ark-thecenter.conf
│   └── ark-extinction.conf
├── GameUserSettings.ini       # Game Server Configuration
├── Game.ini                   # Game Server Configuration
├── ShooterGame.log            # Game log file
├── PlayersJoinNoCheckList.txt # Player whitelist
├── admins.txt                 # Admin whitelist (needs manually setup)
├── start_all.sh               # Start all maps
├── stop_all.sh                # Stop all maps
└── update.sh                  # Update game files (only when all maps stopped)
```

## Installation on Debian 12 or Ubuntu 24.04

To install ARK Survival Ascended Dedicated Server on Debian 12 or Ubuntu 24.04,
download and run [server-install-debian12.sh](server-install-debian12.sh)
as root or sudo.

* Debian 12 tested on Digital Ocean, OVHCloud, and Proxmox.
* Ubuntu 24.04 tested on Proxmox.

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
* Extinction - `ark-extinction`

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

# Start Extinction
sudo systemctl start ark-extinction
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

# Restart Extinction
sudo systemctl restart ark-extinction
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

# Stop Extinction
sudo systemctl stop ark-extinction
```

---

Start all maps (and update game server from Steam):

Will start all **enabled** maps.  If no maps are running, (ie: stop_all was called prior),
it will also issue a Steam game server update prior to starting any maps.

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

# Enable Extinction
sudo systemctl enable ark-extinction
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

# Disable Extinction
sudo systemctl disable ark-extinction
```

Disabling a map will prevent it from starting at boot, but it **will not** stop the map.
use `sudo systemctl stop ...` to stop the requested map manually.

---

### Manually update game servers

Game server code is updated automatically at server boot or when the first map is started,
but you can issue a manual update at any time.

```bash
# Stop all maps first
/home/steam/ArkSurvivalAscended/stop_all.sh
# Start all maps (will issue update during start procedure)
/home/steam/ArkSurvivalAscended/start_all.sh
```

To just update (and not start), the update can be called directly instead.

```bash
# Stop all maps first
/home/steam/ArkSurvivalAscended/stop_all.sh
# Update the game server, but do not start maps
/home/steam/ArkSurvivalAscended/update.sh
```

Attempting to call `update.sh` while a game server is still running will simply result in the script exiting without updating.

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

# Configure start parameters for Extinction
sudo nano /home/steam/ArkSurvivalAscended/services/ark-extinction.conf
```

When done editing command line arguments for the game server, reload the system config:

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

### Cluster sharing across multiple servers

Multi-server clustering is handled by sharing /home/steam/ArkSurvivalAscended/Saved/clusters with NFS.

Primary server generates rules in `/etc/exports` and child servers mount via `/etc/fstab`.

Firewall rules are automatically generated for child servers when their IPs are provided during setup on the master server.
