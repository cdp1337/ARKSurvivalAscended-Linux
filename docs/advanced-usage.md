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
