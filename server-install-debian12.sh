#!/bin/bash
#
# Install script for ARK Survival Ascended on Debian and Ubuntu
#
# Uses Glorious Eggroll's build of Proton
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell - cdp1337@veraciousnetwork.com
# @SOURCE  https://github.com/cdp1337/ARKSurvivalAscended-Linux
#
# F*** Nitrado
#
# Supports:
#   Debian 12
#   Ubuntu 24.04
#
# Requirements:
#   None
#
# TRMM Custom Fields:
#   None
#
# Collection repository: https://github.com/cdp1337/ScriptsCollection

############################################
## Parameter Configuration
############################################

# https://github.com/GloriousEggroll/proton-ge-custom
PROTON_VERSION="9-20"
GAME="ArkSurvivalAscended"
GAME_USER="steam"
GAME_DIR="/home/$GAME_USER/$GAME"
# Force installation directory for game
# steam produces varying results, sometimes in ~/.local/share/Steam, other times in ~/Steam
STEAM_DIR="/home/$GAME_USER/.local/share/Steam"
# Specific "filesystem" directory for installed version of Proton
GAME_COMPAT_DIR="/opt/script-collection/GE-Proton${PROTON_VERSION}/files/share/default_pfx"
# Binary path for Proton
PROTON_BIN="/opt/script-collection/GE-Proton${PROTON_VERSION}/proton"
# List of game maps currently available
GAME_MAPS="ark-island ark-aberration ark-club ark-scorched ark-thecenter ark-extinction"
# Range of game ports to enable in the firewall
PORT_GAME_START=7701
PORT_GAME_END=7706
PORT_RCON_START=27001
PORT_RCON_END=27006


# scriptlet: install/proton/install.sh
##
# Install Glorious Eggroll's Proton fork on a requested version
#
# https://github.com/GloriousEggroll/proton-ge-custom
#
# Will install Proton into /opt/script-collection/GE-Proton${VERSION}
# with its pfx directory in /opt/script-collection/GE-Proton${VERSION}/files/share/default_pfx
#
# @arg $1 string Proton version to install
function install_proton() {
	VERSION="${1:-9-21}"

	echo "Installing Glorious Eggroll's Proton $VERSION..."

	PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${VERSION}/GE-Proton${VERSION}.tar.gz"
	PROTON_TGZ="$(basename "$PROTON_URL")"
	PROTON_NAME="$(basename "$PROTON_TGZ" ".tar.gz")"

	# We will use this directory as a working directory for source files that need downloaded.
	[ -d /opt/script-collection ] || mkdir -p /opt/script-collection

	# Grab Proton from Glorious Eggroll
	if [ ! -e "/opt/script-collection/$PROTON_TGZ" ]; then
		wget "$PROTON_URL" -O "/opt/script-collection/$PROTON_TGZ"
	fi
	# Extract GE Proton into /opt
	if [ ! -e "/opt/script-collection/$PROTON_NAME" ]; then
		tar -x -C /opt/script-collection/ -f "/opt/script-collection/$PROTON_TGZ"
	fi
}
# end-scriptlet: install/proton/install.sh

# scriptlet: checks/firewall/get_firewall.sh
##
# Get which firewall is enabled,
# or "none" if none located
function get_enabled_firewall() {
	if [ "$(systemctl is-active firewalld)" == "active" ]; then
		echo "firewalld"
	elif [ "$(systemctl is-active ufw)" == "active" ]; then
		echo "ufw"
	elif [ "$(systemctl is-active iptables)" == "active" ]; then
		echo "iptables"
	else
		echo "none"
	fi
}
# end-scriptlet: checks/firewall/get_firewall.sh

# scriptlet: checks/os/os_like.sh
##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_debian() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'debian' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'debian' ]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_ubuntu() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'ubuntu' ]]; then echo 1; return; fi
		if [ "$ID" == 'ubuntu' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_rhel() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'rhel' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'fedora' ]]; then echo 1; return; fi
		if [[ "$LIKE" =~ 'centos' ]]; then echo 1; return; fi
		if [ "$ID" == 'rhel' ]; then echo 1; return; fi
		if [ "$ID" == 'fedora' ]; then echo 1; return; fi
		if [ "$ID" == 'centos' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_suse() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'suse' ]]; then echo 1; return; fi
		if [ "$ID" == 'suse' ]; then echo 1; return; fi
	fi

	echo 0
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_arch() {
	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ 'arch' ]]; then echo 1; return; fi
		if [ "$ID" == 'arch' ]; then echo 1; return; fi
	fi

	echo 0
}
# end-scriptlet: checks/os/os_like.sh

# scriptlet: install/steam/install-steamcmd.sh

##
# Install SteamCMD
function install_steamcmd() {
	echo "Installing SteamCMD..."

	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_UBUNTU="$(os_like_ubuntu)"

	# Preliminary requirements
	if [ "$TYPE_UBUNTU" == 1 ]; then
		add-apt-repository -y multiverse
		dpkg --add-architecture i386
		apt update

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		apt install -y steamcmd
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		dpkg --add-architecture i386
		apt update
		apt install -y software-properties-common apt-transport-https dirmngr ca-certificates lib32gcc-s1

		# Enable "non-free" repos for Debian (for steamcmd)
		# https://stackoverflow.com/questions/76688863/apt-add-repository-doesnt-work-on-debian-12
		add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free
		if [ $? -ne 0 ]; then
			echo "Workaround failed to add non-free repos, trying new method instead"
			apt-add-repository -y non-free
		fi

		# Install steam repo
		curl -s http://repo.steampowered.com/steam/archive/stable/steam.gpg > /usr/share/keyrings/steam.gpg
		echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list

		# By using this script, you agree to the Steam license agreement at https://store.steampowered.com/subscriber_agreement/
		# and the Steam privacy policy at https://store.steampowered.com/privacy_agreement/
		# Since this is meant to support unattended installs, we will forward your acceptance of their license.
		echo steam steam/question select "I AGREE" | debconf-set-selections
		echo steam steam/license note '' | debconf-set-selections

		# Install steam binary and steamcmd
		apt update
		apt install -y steamcmd
	else
		echo 'Unsupported or unknown OS' >&2
		exit 1
	fi
}
# end-scriptlet: install/steam/install-steamcmd.sh

# scriptlet: install/firewalld/install.sh

##
# Install firewalld
#
function install_firewalld() {
	echo "Installing firewalld..."

	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_RHEL="$(os_like_rhel)"
	TYPE_ARCH="$(os_like_arch)"
	TYPE_SUSE="$(os_like_suse)"

	if [ "$TYPE_DEBIAN" == 1 ]; then
		apt update
		apt install -y firewalld
	elif [ "$TYPE_RHEL" == 1 ]; then
		dnf install -y firewalld
	elif [ "$TYPE_ARCH" == 1 ]; then
		pacman -Syu --noconfirm firewalld
	elif [ "$TYPE_SUSE" == 1 ]; then
		zypper ref
		zypper install -y firewalld
	else
		echo 'Unsupported or unknown OS' >&2
		exit 1
	fi
}
# end-scriptlet: install/firewalld/install.sh




############################################
## Pre-exec Checks
############################################

# Only allow running as root
# @todo Check if `su -` is actually required here; will just `sudo` work instead?
if [ "$LOGNAME" != "root" ]; then
	echo "Please run this script as root! (If you ran with 'su', use 'su -' instead)" >&2
	exit 1
fi

# This script can run on an existing server, but should not update the game if a map is actively running.
# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		RUNNING=1
	fi
done

# Determine if this is a new installation or an upgrade (/repair)
if [ -e /etc/systemd/system/ark-island.service ]; then
	INSTALLTYPE="upgrade"
else
	INSTALLTYPE="new"
fi

if [ -e "$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64/PlayersJoinNoCheckList.txt" ]; then
	WHITELIST=1
else
	WHITELIST=0
fi

if [ -n "$(grep "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" /etc/exports 2>/dev/null)" ]; then
	MULTISERVER=1
	ISPRIMARY=1
elif [ $(egrep -q "^[0-9\.]*:$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" /etc/fstab) ]; then
	MULTISERVER=1
	ISPRIMARY=0
	PRIMARYIP="$(grep "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" /etc/fstab | sed 's#^\(.*\):.*#\1#')"
else
	MULTISERVER=0
	ISPRIMARY=0
fi

# Determine if there is a firewall already installed, (to prevent issues)
# Addresses Issue #19
FIREWALL=$(get_enabled_firewall)


############################################
## User Prompts (pre setup)
############################################

# Ask the user some information before installing.
echo "================================================================================"
echo "         	  ARK Survival Ascended *unofficial* Installer"
echo ""
if [ "$INSTALLTYPE" == "new" ]; then
	echo "? What is the community name of the server? (e.g. My Awesome ARK Server)"
	echo -n "> "
	read COMMUNITYNAME
	if [ "$COMMUNITYNAME" == "" ]; then
		COMMUNITYNAME="My Awesome ARK Server"
	fi
fi

echo ''
if [ "$WHITELIST" -eq 1 ]; then
	echo "? DISABLE whitelist for players?"
	echo -n "> (y/N): "
	read WHITELIST
	if [ "$WHITELIST" == "y" -o "$WHITELIST" == "Y" ]; then
		WHITELIST=0
	else
		WHITELIST=1
	fi
else
	echo "? Enable whitelist for players?"
	echo -n "> (y/N): "
	read WHITELIST
	if [ "$WHITELIST" == "y" -o "$WHITELIST" == "Y" ]; then
		WHITELIST=1
	else
		WHITELIST=0
	fi
fi

echo ''
if [ "$MULTISERVER" -eq 1 ]; then
	echo "? DISABLE multi-server cluster support? (Maps spread across different servers)"
	echo -n "> (y/N): "
	read MULTISERVER
	if [ "$MULTISERVER" == "y" -o "$MULTISERVER" == "Y" ]; then
		MULTISERVER=0
	else
		MULTISERVER=1
	fi

	if [ "$MULTISERVER" -eq 1 -a "$ISPRIMARY" -eq 1 ]; then
		echo ''
		echo "? Add more secondary IPs to the cluster? (Separate different IPs with spaces, enter to just skip)"
		echo -n "> "
		read SECONDARYIPS
	fi
else
	echo "? Enable multi-server cluster support? (Maps spread across different servers)"
	echo -n "> (y/N): "
	read MULTISERVER
	if [ "$MULTISERVER" == "y" -o "$MULTISERVER" == "Y" ]; then
		MULTISERVER=1
	else
		MULTISERVER=0
	fi

	if [ "$MULTISERVER" -eq 1 ]; then
		echo ''
		echo "? Is this the first (primary) server?"
		echo -n "> (y/N): "
		read ISPRIMARY
		if [ "$ISPRIMARY" == "y" -o "$ISPRIMARY" == "Y" ]; then
			ISPRIMARY=1
		else
			ISPRIMARY=0
		fi

		if [ "$ISPRIMARY" -eq 1 ]; then
			echo ''
			echo "? What are the IPs of the secondary servers? (Separate different IPs with spaces)"
			echo -n "> "
			read SECONDARYIPS
		else
			echo ''
			echo "? What is the IP of the primary server?"
			echo -n "> "
			read PRIMARYIP
		fi
	fi
fi


############################################
## Dependency Installation and Setup
############################################

# Create a "steam" user account
# This will create the account with no password, so if you need to log in with this user,
# run `sudo passwd steam` to set a password.
if [ -z "$(getent passwd $GAME_USER)" ]; then
	useradd -m -U $GAME_USER
fi

# Preliminary requirements
apt install -y curl wget sudo

if [ "$FIREWALL" == "none" ]; then
	# No firewall installed, go ahead and install firewalld
	install_firewalld
fi

if [ "$MULTISERVER" -eq 1 ]; then
	if [ "$ISPRIMARY" -eq 1 ]; then
		apt install -y nfs-kernel-server nfs-common
	else
		apt install -y nfs-common
	fi
fi

# Install steam binary and steamcmd
install_steamcmd

# Grab Proton from Glorious Eggroll
install_proton "$PROTON_VERSION"


############################################
## Upgrade Checks
############################################

for MAP in $GAME_MAPS; do
	# Ensure the override directory exists for the admin modifications to the CLI arguments.
	[ -e /etc/systemd/system/${MAP}.service.d ] || mkdir -p /etc/systemd/system/${MAP}.service.d

	# Release 2023.10.31 - Issue #8
	if [ -e /etc/systemd/system/${MAP}.service ]; then
		# Check if the service is already installed and move any modifications to the override.
		# This is important for existing installs so the admin modifications to CLI arguments do not get overwritten.

		if [ ! -e /etc/systemd/system/${MAP}.service.d/override.conf ]; then
			# Override does not exist yet, merge in any changes in the default service file.
			SERVICE_EXEC_LINE="$(grep -E '^ExecStart=' /etc/systemd/system/${MAP}.service)"

			cat > /etc/systemd/system/${MAP}.service.d/override.conf <<EOF
[Service]
$SERVICE_EXEC_LINE
EOF
		fi
	fi
done
## End Release 2023.10.31 - Issue #8


############################################
## Game Installation
############################################

# Install ARK Survival Ascended Dedicated
if [ $RUNNING -eq 1 ]; then
	echo "WARNING - One or more game servers are currently running, this script will not update the game files."
	echo "Skipping steam update"
else
	sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update 2430930 validate +quit
    # STAGING / TESTING - skip ark because it's huge; AppID 90 is Team Fortress 1 (a tiny server useful for testing)
    #sudo -u steam /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update 90 validate +quit
    if [ $? -ne 0 ]; then
    	echo "Could not install ARK Survival Ascended Dedicated Server, exiting" >&2
    	exit 1
    fi
fi

# Install the systemd service files for ARK Survival Ascended Dedicated Server
for MAP in $GAME_MAPS; do
	# Different maps will have different settings, (to allow them to coexist on the same server)
	if [ "$MAP" == "ark-island" ]; then
		DESC="Island"
		NAME="TheIsland_WP"
		MODS=""
		GAMEPORT=7701
		RCONPORT=27001
	elif [ "$MAP" == "ark-aberration" ]; then
		DESC="Aberration"
		NAME="Aberration_WP"
		MODS=""
		GAMEPORT=7702
		RCONPORT=27002
	elif [ "$MAP" == "ark-club" ]; then
		DESC="Club"
		NAME="BobsMissions_WP"
		MODS="1005639"
		GAMEPORT=7703
		RCONPORT=27003
	elif [ "$MAP" == "ark-scorched" ]; then
		DESC="Scorched"
		NAME="ScorchedEarth_WP"
		MODS=""
		GAMEPORT=7704
		RCONPORT=27004
	elif [ "$MAP" == "ark-thecenter" ]; then
		DESC="TheCenter"
		NAME="TheCenter_WP"
		MODS=""
		GAMEPORT=7705
		RCONPORT=27005
	elif [ "$MAP" == "ark-extinction" ]; then
		DESC="Extinction"
		NAME="Extinction_WP"
		MODS=""
		GAMEPORT=7706
		RCONPORT=27006
	fi


	# Install system service file to be loaded by systemd
	cat > /etc/systemd/system/${MAP}.service <<EOF
[Unit]
# DYNAMICALLY GENERATED FILE! Edit at your own risk
Description=ARK Survival Ascended Dedicated Server (${DESC})
After=network.target
After=ark-updater.service

[Service]
Type=simple
LimitNOFILE=10000
User=$GAME_USER
Group=$GAME_USER
WorkingDirectory=$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
Environment="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_DIR"
Environment="STEAM_COMPAT_DATA_PATH=$GAME_DIR/prefixes/$MAP"
# Check $GAME_DIR/services to adjust the CLI arguments
Restart=on-failure
RestartSec=20s

[Install]
WantedBy=multi-user.target
EOF

	if [ ! -e /etc/systemd/system/${MAP}.service.d/override.conf ]; then
		# Override does not exist yet, create boilerplate file.
		# This is the main file that the admin will use to modify CLI arguments,
		# so we do not want to overwrite their work if they have already modified it.
		cat > /etc/systemd/system/${MAP}.service.d/override.conf <<EOF
[Service]
# Edit this line to adjust start parameters of the server
# After modifying, please remember to run `sudo systemctl daemon-reload` to apply changes to the system.
ExecStart=$PROTON_BIN run ArkAscendedServer.exe ${NAME}?listen?SessionName="${COMMUNITYNAME} (${DESC})"?RCONPort=${RCONPORT} -port=${GAMEPORT} -servergamelog -mods=$MODS
EOF
    fi

    # Set the owner of the override to steam so that user account can modify it.
    chown $GAME_USER:$GAME_USER /etc/systemd/system/${MAP}.service.d/override.conf

    if [ ! -e $GAME_DIR/prefixes/$MAP ]; then
    	# Install a new prefix for this specific map
    	# Proton 9 seems to have issues with launching multiple binaries in the same prefix.
    	[ -d $GAME_DIR/prefixes ] || sudo -u $GAME_USER mkdir -p $GAME_DIR/prefixes
		sudo -u $GAME_USER cp $GAME_COMPAT_DIR $GAME_DIR/prefixes/$MAP -r
	fi
done

# Create update helper and service
# Install system service file to be loaded by systemd
cat > /etc/systemd/system/ark-updater.service <<EOF
[Unit]
# DYNAMICALLY GENERATED FILE! Edit at your own risk
Description=ARK Survival Ascended Dedicated Server Updater
After=network.target

[Service]
Type=oneshot
User=$GAME_USER
Group=$GAME_USER
WorkingDirectory=$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
ExecStart=$GAME_DIR/update.sh

[Install]
WantedBy=multi-user.target
EOF

cat > $GAME_DIR/update.sh <<EOF
#!/bin/bash
#
# Update ARK Survival Ascended Dedicated Server
#
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# List of all maps available on this platform
GAME_MAPS="$GAME_MAPS"

# This script is expected to be run as the steam user, (as that is the owner of the game files).
# If another user calls this script, sudo will be used to switch to the steam user.
if [ "\$(whoami)" == "$GAME_USER" ]; then
	SUDO_NEEDED=0
else
	SUDO_NEEDED=1
fi

function update_game {
	echo "Running game update"
	if [ "\$SUDO_NEEDED" -eq 1 ]; then
		sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update 2430930 validate +quit
	else
		/usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update 2430930 validate +quit
	fi

	if [ \$? -ne 0 ]; then
		echo "Game update failed!" >&2
		exit 1
	fi
}

# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-active $MAP)" == "active" ]; then
		RUNNING=1
	fi
done
if [ \$RUNNING -eq 0 ]; then
	update_game
else
	echo "Game server is already running, not updating"
fi
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/update.sh
chmod +x $GAME_DIR/update.sh
systemctl daemon-reload
systemctl enable ark-updater


# Create start/stop helpers for all maps
cat > $GAME_DIR/start_all.sh <<EOF
#!/bin/bash
#
# Start all ARK server maps that are enabled
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# List of all maps available on this platform
GAME_MAPS="$GAME_MAPS"

function start_game {
	echo "Starting game instance \$1..."
	sudo systemctl start \$1
	echo "Waiting 60 seconds for threads to start"
	for i in {0..9}; do
		sleep 6
		echo -n '.'
	done
	# Check status real quick
	sudo systemctl status \$1 | grep Active
}

function update_game {
	echo "Running game update"
	sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update 2430930 validate +quit
	if [ \$? -ne 0 ]; then
		echo "Game update failed, not starting"
		exit 1
	fi
}

RUNNING=0
for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-active $MAP)" == "active" ]; then
		RUNNING=1
	fi
done
if [ \$RUNNING -eq 0 ]; then
	update_game
else
	echo "Game server is already running, not updating"
fi

for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-enabled \$MAP)" == "enabled" -a "\$(systemctl is-active \$MAP)" == "inactive" ]; then
		start_game \$MAP
	fi
done
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/start_all.sh
chmod +x $GAME_DIR/start_all.sh


cat > $GAME_DIR/stop_all.sh <<EOF
#!/bin/bash
#
# Stop all ARK server maps that are enabled
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# List of all maps available on this platform
GAME_MAPS="$GAME_MAPS"

function stop_game {
	echo "Stopping game instance \$1..."
	sudo systemctl stop \$1
	echo "Waiting 10 seconds for threads to settle"
	for i in {0..9}; do
		echo -n '.'
		sleep 1
	done
	# Check status real quick
	sudo systemctl status \$1 | grep Active
}

for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-enabled \$MAP)" == "enabled" -a "\$(systemctl is-active \$MAP)" == "active" ]; then
		stop_game \$MAP
	fi
done
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/stop_all.sh
chmod +x $GAME_DIR/stop_all.sh


# Reload systemd to pick up the new service files
systemctl daemon-reload

# Ensure cluster resources exist
[ -d "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters"


############################################
## NFS Configuration
############################################

if [ "$MULTISERVER" -eq 1 ]; then
	# Enable / ensure enabled shared directory for multi-server support
	if [ "$ISPRIMARY" -eq 1 ]; then
		systemctl enable nfs-server
		for IP in $SECONDARYIPS; do
			# Ensure the cluster folder is shared with the various child servers
			if [ ! $(grep -q "Saved/clusters $IP" /etc/exports) ]; then
				echo "Adding $IP to NFS access for $GAME_DIR/AppFiles/ShooterGame/Saved/clusters"
				echo "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters $IP/32(rw,sync,no_subtree_check)" >> /etc/exports
			fi
		done
		systemctl restart nfs-server
	else
		if [ ! $(grep -q "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" /etc/fstab) ]; then
			echo "Adding NFS mount to $PRIMARYIP for $GAME_DIR/AppFiles/ShooterGame/Saved/clusters"
			echo "$PRIMARYIP:$GAME_DIR/AppFiles/ShooterGame/Saved/clusters $GAME_DIR/AppFiles/ShooterGame/Saved/clusters nfs defaults,rw,sync,soft,intr 0 0" >> /etc/fstab
			mount -a
		fi
	fi
else
	# Disable / ensure disabled shared directory for multi-server support
	if [ -n "$(grep "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" /etc/exports 2>/dev/null)" ]; then
		echo "Disabling cluster share"
		BAK="/etc/exports.bak-$(date +%Y%m%d%H%M%S)"
		cp /etc/exports $BAK
		cat $BAK | grep -v "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" > /etc/exports
		systemctl restart nfs-server
	fi
	if [ -n "$(mount | grep "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" | grep nfs)" ]; then
		echo "Unmounting cluster share"
		umount "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters"
	fi
	if [ $(egrep -q "^[0-9\.]*:$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" /etc/fstab) ]; then
		echo "Removing NFS mount from fstab"
		BAK="/etc/fstab.bak-$(date +%Y%m%d%H%M%S)"
		cp /etc/fstab $BAK
		cat $BAK | grep -v "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" > /etc/fstab
	fi
fi

# Ensure cluster resources exist
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/PlayersJoinNoCheckList.txt"
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/admins.txt"

############################################
## Security Configuration
############################################

if [ "$FIREWALL" == "ufw" ]; then
	# Enable rules for UFW
	ufw allow ${PORT_GAME_START}:${PORT_GAME_END}/udp
	ufw allow ${PORT_RCON_START}:${PORT_RCON_END}/tcp
	if [ "$MULTISERVER" -eq 1 -a "$ISPRIMARY" -eq 1 ]; then
		# Allow NFS access from secondary servers
		for IP in $SECONDARYIPS; do
			ufw allow from $IP/32 to any port nfs
		done
	fi
elif [ "$FIREWALL" == "firewalld" ]; then
	# Install/enable rules for Firewalld
	[ -d "/etc/firewalld/services" ] || mkdir -p /etc/firewalld/services
    cat > /etc/firewalld/services/ark-survival.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>ARK Survival Ascended</short>
  <description>ARK Survival Ascended game server</description>
  <port port="${PORT_GAME_START}-${PORT_GAME_END}" protocol="udp"/>
  <port port="${PORT_RCON_START}-${PORT_RCON_END}" protocol="tcp"/>
</service>
EOF
	systemctl restart firewalld
    firewall-cmd --permanent --zone=public --add-service=ark-survival

    if [ "$MULTISERVER" -eq 1 -a "$ISPRIMARY" -eq 1 ]; then
		# Allow NFS access from secondary servers
		firewall-cmd --permanent --zone=internal --add-service=nfs
		for IP in $SECONDARYIPS; do
			firewall-cmd --permanent --zone=internal --add-source="$IP/32"
		done
	fi
fi


############################################
## Post-Install Configuration
############################################


# Setup whitelist
WL_GAME="$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64/PlayersJoinNoCheckList.txt"
WL_CLUSTER="$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/PlayersJoinNoCheckList.txt"
if [ -e "$WL_GAME" -a ! -h "$WL_GAME" ]; then
	# Whitelist already exists in the game directory, either move it to the cluster directory
	# or back it up.  This is because this script will manage the whitelist via a symlink.
	if [ -s "$WL_CLUSTER" ]; then
		# Cluster whitelist already exists, move the game whitelist to a backup
		sudo -u $GAME_USER mv "$WL_GAME" "$WL_GAME.bak"
	else
		# Cluster whitelist does not exist, move the game whitelist to the cluster directory
		sudo -u $GAME_USER mv "$WL_GAME" "$WL_CLUSTER"
	fi
fi

if [ "$WHITELIST" -eq 1 ]; then
	# User opted to enable (or keep enabled) whitelist
	if [ -h "$WL_GAME" ]; then
		# Whitelist is already a symlink, (default), do nothing
		echo "Whitelist already enabled"
	else
		# Whitelist is not a symlink, (default), create one
		echo "Enabling player whitelist"
		sudo -u $GAME_USER ln -s "$WL_CLUSTER" "$WL_GAME"
	fi
else
	# User opted to disable whitelist
	if [ -h "$WL_GAME" ]; then
		# Whitelist is already a symlink, (default), remove it
		echo "Disabling player whitelist"
		sudo -u $GAME_USER unlink "$WL_GAME"
	else
		# Whitelist is not a symlink, (default), do nothing
		echo "Whitelist already disabled"
	fi
fi


# Create some helpful links for the user.
[ -e "$GAME_DIR/services" ] || sudo -u steam mkdir -p "$GAME_DIR/services"
for MAP in $GAME_MAPS; do
	[ -h "$GAME_DIR/services/${MAP}.conf" ] || sudo -u steam ln -s /etc/systemd/system/${MAP}.service.d/override.conf "$GAME_DIR/services/${MAP}.conf"
done
[ -h "$GAME_DIR/GameUserSettings.ini" ] || sudo -u steam ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini "$GAME_DIR/GameUserSettings.ini"
[ -h "$GAME_DIR/Game.ini" ] || sudo -u steam ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/Game.ini "$GAME_DIR/Game.ini"
[ -h "$GAME_DIR/ShooterGame.log" ] || sudo -u steam ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/Logs/ShooterGame.log "$GAME_DIR/ShooterGame.log"
[ -h "$GAME_DIR/PlayersJoinNoCheckList.txt" ] || sudo -u $GAME_USER ln -s "$WL_CLUSTER" "$GAME_DIR/PlayersJoinNoCheckList.txt"
[ -h "$GAME_DIR/admins.txt" ] || sudo -u steam ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/clusters/admins.txt "$GAME_DIR/admins.txt"


echo "================================================================================"
echo "If everything went well, ARK Survival Ascended should be installed!"
echo ""
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-enabled $MAP)" == "enabled" ]; then
		echo "Game map ${MAP} is already enabled"
	else
		echo "? Enable game map ${MAP}? (y/N)"
		echo -n "> "
		read OPT
		if [ "$OPT" == "y" -o "$OPT" == "Y" ]; then
			systemctl enable $MAP
		else
			echo "Not enabling ${MAP}, you can always enable it in the future with 'sudo systemctl enable $MAP'"
		fi
	fi
	echo ""
done
echo ""
echo "To restart a map:      sudo systemctl restart NAME-OF-MAP"
echo "To start a map:        sudo systemctl start NAME-OF-MAP"
echo "To stop a map:         sudo systemctl stop NAME-OF-MAP"
echo "Game files:            $GAME_DIR/AppFiles/"
echo "Runtime configuration: $GAME_DIR/services/"
echo "Game log:              $GAME_DIR/ShooterGame.log"
echo "Game user settings:    $GAME_DIR/GameUserSettings.ini"
if [ "$WHITELIST" -eq 1 ]; then
	echo "Whitelist:             $GAME_DIR/PlayersJoinNoCheckList.txt"
fi
echo "Admin list:            $GAME_DIR/admin.txt"
echo "To start all maps:     $GAME_DIR/start_all.sh"
echo "To stop all maps:      $GAME_DIR/stop_all.sh"
echo "To update game:        $GAME_DIR/update.sh"
