# Tools for installing ARK Survival Ascended Dedicated Server on Linux

Wanna chat?

[![Discord](https://img.shields.io/discord/909843670214258729?label=Discord)](https://discord.gg/48hHdm5EgA)

Help fund the project

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q5Q013RM9Q)


## What does it do?

This script will:

* Download Proton from Glorious Eggroll's build
* Install Steam and SteamCMD
* Create a `steam` user for running the game server
* Install ARK Survival Ascended Dedicated Server using standard Steam procedures
* Setup a systemd service for running the game server
* Add firewall service for game server (with firewalld or UFW)
* Setup NFS shares for multi-server environments
* Adds a management script for controlling your server

---

## Installation on Debian 12 or Ubuntu 24.04

To install ARK Survival Ascended Dedicated Server on Debian 12 or Ubuntu 24.04,
download and run [server-install-debian12.sh](dist/server-install-debian12.sh)
as root or sudo.

* Debian 12 tested on Digital Ocean, OVHCloud, and Proxmox.
* Ubuntu 24.04 tested on Proxmox.

Quick run (if you trust me, which you of course should not):

```bash
sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/cdp1337/ARKSurvivalAscended-Linux/main/dist/server-install-debian12.sh)" root
```

### Advanced Usage

Download the script and retain for later management use.

```bash
wget https://raw.githubusercontent.com/cdp1337/ARKSurvivalAscended-Linux/main/dist/server-install-debian12.sh
chmod +x server-install-debian12.sh

# Reset and rebuild proton directories (if the prefix gets corrupted somehow)
sudo ./server-install-debian12.sh --reset-proton

# Force reinstall game binaries, (useful after a major update when Wildcard breaks the build)
# This will NOT remove your save data!
sudo ./server-install-debian12.sh --force-reinstall
```

Re-running the installation script on an existing server **is safe** and will **not** overwrite or delete your existing game data.

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
│   ├── ark-extinction/
│   └── ark-astraeos/
├── services/                  # Service file overrides (for setting startup options)
│   ├── ark-aberration.conf
│   ├── ark-club.conf
│   ├── ark-island.conf
│   ├── ark-scorched.conf
│   ├── ark-thecenter.conf
│   ├── ark-extinction.conf
│   └── ark-astraeos.conf
├── GameUserSettings.ini       # Game Server Configuration
├── Game.ini                   # Game Server Configuration
├── ShooterGame.log            # Game log file
├── PlayersJoinNoCheckList.txt # Player whitelist
├── admins.txt                 # Admin whitelist (needs manually setup)
├── start_all.sh               # Start all maps
├── stop_all.sh                # Stop all maps
├── update.sh                  # Update game files (only when all maps stopped)
└── manage.py                  # Management console for game server, maps, and settings
```



## Managing your Server (Easy Method)

Once installed, run `sudo /home/steam/ArkSurvivalAscended/manage.py` to access the management console:

```
| # | Map              | Session                    | Port | RCON  | Auto-Start | Service | Players |
| 1 | ScorchedEarth_WP | VN Test Boxes (Scorched)   | 7704 | 27004 | Enabled    | Stopped | N/A     |
| 2 | TheIsland_WP     | VN Test Boxes (Island)     | 7701 | 27001 | Disabled   | Stopped | N/A     |
| 3 | TheCenter_WP     | VN Test Boxes (TheCenter)  | 7705 | 27005 | Disabled   | Stopped | N/A     |
| 4 | Astraeos_WP      | VN Test Boxes (Astraeos)   | 7707 | 27007 | Disabled   | Stopped | N/A     |
| 5 | Aberration_WP    | VN Test Boxes (Aberration) | 7702 | 27002 | Disabled   | Stopped | N/A     |
| 6 | Extinction_WP    | VN Test Boxes (Extinction) | 7706 | 27006 | Disabled   | Stopped | N/A     |
| 7 | BobsMissions_WP  | VN Test Boxes (Club)       | 7703 | 27003 | Disabled   | Stopped | N/A     |

1-7 to manage individual map settings
Configure: [M]ods | [C]luster | [A]dmin password/RCON | re[N]ame
Control: [S]tart all | s[T]op all | [R]estart all | [U]pdate
or [Q]uit to exit
```

The main screen of the management UI shows all maps and some basic info, 
including how many players are currently connected.

### Mods management

Pressing `m` will open the mods overview screen:

```
| Session                    | Mods    |
| VN Test Boxes (Scorched)   |         |
| VN Test Boxes (Island)     |         |
| VN Test Boxes (TheCenter)  |         |
| VN Test Boxes (Astraeos)   |         |
| VN Test Boxes (Aberration) |         |
| VN Test Boxes (Extinction) |         |
| VN Test Boxes (Club)       | 1005639 |

[E]nable mod on all maps | [D]isable mod on all maps | [B]ack:
```

Here, `e` will allow you to enable a mod on all maps and `d` will disable a mod on all maps.

`b` will go back to the main menu overview.

### Cluster management

Pressing `c` will open the cluster overview screen:

```
| Session                    | Cluster ID     |
| VN Test Boxes (Scorched)   | some-test-name |
| VN Test Boxes (Island)     | some-test-name |
| VN Test Boxes (TheCenter)  | some-test-name |
| VN Test Boxes (Astraeos)   | some-test-name |
| VN Test Boxes (Aberration) | some-test-name |
| VN Test Boxes (Extinction) | some-test-name |
| VN Test Boxes (Club)       | some-test-name |

[C]hange cluster id on all maps | [B]ack:
```

Pressing `c` on the cluster page will allow you to set the cluster ID for all maps.

`b` will go back to the main menu overview.

### Admin password and RCON management

Pressing `a` will open the admin password and RCON management screen:

```
| Session                    | Admin Password | RCON  |
| VN Test Boxes (Scorched)   | foobarblaz     | 27004 |
| VN Test Boxes (Island)     | foobarblaz     | 27001 |
| VN Test Boxes (TheCenter)  | foobarblaz     | 27005 |
| VN Test Boxes (Astraeos)   | foobarblaz     | 27007 |
| VN Test Boxes (Aberration) | foobarblaz     | 27002 |
| VN Test Boxes (Extinction) | foobarblaz     | 27006 |
| VN Test Boxes (Club)       | foobarblaz     | 27003 |

[C]hange admin password on all | [E]nable RCON on all | [D]isable RCON on all | [B]ack:
```

This allows you to change the admin/rcon password across all maps, as well as enable or disable RCON.

Note, you should leave RCON enabled, as it allows the script to warn users upon restarts and 
gracefully save prior to shutting down the server. 


### Renaming maps

From the main menu overview, pressing `n` will allow you to rename all maps.
By default, all maps are suffixed with the map name, allowing you to have the same name
for every map in the cluster.

### Stopping / Starting / Restarting

From the main menu overview, the options `s`, `t`, and `r` respectively
will **s**tart, s**t**op, and **r**estart all maps that are currently enabled.

When RCON is enabled and available, (default), the stop logic will first check if there are 
any players currently on the map.  If there are, it will send a 5-minute warning to all players
and then wait for a minute before another warning is sent if they are still logged in.

![Preview of output in game](images/server-shutdown-notice.png)

3 minutes, 2 minutes, 1 minute, and 30 second warnings are also sent.

If all players have left the map prior to the countdown completing, 
the server will skip the remaining countdown and will proceed with the shutdown.

A world save is automatically requested on the map prior to shutdown.

### Updating

If all maps are stopped, the `u` option will update the game server files from Steam.

### Managing individual maps

Pressing 1 through (however many maps there are), will open the individual map page.

```
Map:           ScorchedEarth_WP
Session:       VN Test Boxes (Scorched)
Port:          7704
RCON:          27004
Auto-Start:    Yes
Status:        Stopped
Players:       None
Mods:          
Cluster ID:    some-test-name
Other Options: AllowFlyerCarryPvE=True?DinoDamageMultiplier=25
Other Flags:   -servergamelog     

[E]nable | [D]isable | [M]ods | [C]luster | re[N]ame | [F]lags | [O]ptions | [S]tart | s[T]op | [R]estart | [B]ack:
```

This page allows you to configure a specific map, notably enabling, disabling, and configuring flags and options.

Options are any variable as defined in the [Server Configuration](https://ark.wiki.gg/wiki/Server_configuration)
and flags are command line arguments (ie: those that start with a `-`.)


## Managing with systemd (manual method)

A list of all maps and their relative systemd service name: 

* Island - `ark-island`
* Aberration - `ark-aberration`
* Club ARK - `ark-club`
* Scorched - `ark-scorched`
* The Center - `ark-thecenter`
* Extinction - `ark-extinction`
* Astraeos - `ark-astraeos`

### Start, Stop, Restart

Start a single map:

```bash
sudo systemctl start MAP_SERVICE_NAME
```

---

Restarting a single map:

```bash
sudo systemctl restart MAP_SERVICE_NAME
```

Warning: issuing a restart manually will immediately stop the map,
kicking any user without warning and sometimes losing a few minutes of progress.

---

Stopping a single map:

```bash
sudo systemctl stop MAP_SERVICE_NAME
```

Warning: issuing a stop manually will immediately stop the map, 
kicking any user without warning and sometimes losing a few minutes of progress.

---

### Enable and disable maps

```bash
sudo systemctl enable MAP_SERVICE_NAME
```

Enabling a map will set it to start at boot, but it **will not** start the map immediately.
use `sudo systemctl start ...` to start the requested map manually.

---

```bash
sudo systemctl disable MAP_SERVICE_NAM
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

## Utilized libraries

* [RCON library by Conqp](https://github.com/conqp/rcon) (GPLv3)
* [Scripts Collection compiler by eVAL](https://github.com/eVAL-Agency/ScriptsCollection) (AGPLv3)
* [Proton-GE by Glorious Eggroll](https://github.com/GloriousEggroll/proton-ge-custom) (BSD-3)
* [SteamCMD by Valve](https://developer.valvesoftware.com/wiki/SteamCMD)
* curl 
* wget 
* sudo
* systemd
* python3
* python3-venv
* ufw
* nfs-kernel-server 
* nfs-common