#!/bin/bash
#
# Install script for ARK Survival Ascended on Debian 12
#
# Uses Glorious Eggroll's build of Proton
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell - cdp1337@veraciousnetwork.com
# @SOURCE  https://github.com/cdp1337/ARKSurvivalAscended-Linux
#
# F*** Nitrado


############################################
## Parameter Configuration
############################################

# https://github.com/GloriousEggroll/proton-ge-custom
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-20/GE-Proton9-20.tar.gz"
PROTON_TGZ="$(basename "$PROTON_URL")"
PROTON_NAME="$(basename "$PROTON_TGZ" ".tar.gz")"
# Force installation directory for game
# steam produces varying results, sometimes in ~/.local/share/Steam, other times in ~/Steam
GAMEDIR="/home/steam/ArkSurvivalAscended"
STEAMDIR="/home/steam/.local/share/Steam"
# Wine/Proton compatiblity directory
COMPATDIR="$STEAMDIR/compatibilitytools.d"
# Specific "filesystem" directory for installed version of Proton
GAMECOMPATDIR="$COMPATDIR/$PROTON_NAME/files/share/default_pfx"
# Binary path for Proton
PROTONBIN="$COMPATDIR/$PROTON_NAME/proton"
# List of game maps currently available
GAMEMAPS="ark-island ark-aberration ark-club ark-scorched ark-thecenter"


############################################
## Pre-exec Checks
############################################

# Only allow running as root
if [ "$LOGNAME" != "root" ]; then
	echo "Please run this script as root! (If you ran with 'su', use 'su -' instead)" >&2
	exit 1
fi

# This script can run on an existing server, but should not run while the game is actively running.
if [ $(ps aux | grep ArkAscendedServer.exe | wc -l) -gt 1 ]; then
	echo "It appears that the ARK server is already running, please stop it before running this script."
	exit 1
fi


############################################
## User Prompts (pre setup)
############################################

# Ask the user some information before installing.
echo "================================================================================"
echo "         	  ARK Survival Ascended *unofficial* Installer"
echo ""
echo "? What is the community name of the server? (e.g. My Awesome ARK Server)"
echo -n "> "
read COMMUNITYNAME
if [ "$COMMUNITYNAME" == "" ]; then
	COMMUNITYNAME="My Awesome ARK Server"
fi


############################################
## Dependency Installation and Setup
############################################

# Create a "steam" user account
# This will create the account with no password, so if you need to log in with this user,
# run `sudo passwd steam` to set a password.
[ -d /home/steam ] || useradd -m -U steam


# We will use this directory as a working directory for source files that need downloaded.
[ -d /opt/game-resources ] || mkdir -p /opt/game-resources


# Preliminary requirements
dpkg --add-architecture i386
apt update
apt install -y software-properties-common apt-transport-https dirmngr ca-certificates curl wget sudo firewalld


# Enable "non-free" repos for Debian (for steamcmd)
# https://stackoverflow.com/questions/76688863/apt-add-repository-doesnt-work-on-debian-12
add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free


# Install steam repo
curl -s http://repo.steampowered.com/steam/archive/stable/steam.gpg > /usr/share/keyrings/steam.gpg
echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list


# Install steam binary and steamcmd
apt update
apt install -y lib32gcc-s1 steamcmd


# Grab Proton from Glorious Eggroll
if [ ! -e "/opt/game-resources/$PROTON_TGZ" ]; then
	wget "$PROTON_URL" -O "/opt/game-resources/$PROTON_TGZ"
fi
# Extract GE Proton into this user's Steam path
[ -d "$COMPATDIR" ] || sudo -u steam mkdir -p "$COMPATDIR"
sudo -u steam tar -x -C "$COMPATDIR/" -f "/opt/game-resources/$PROTON_TGZ"


############################################
## Upgrade Checks
############################################

for MAP in $GAMEMAPS; do
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
sudo -u steam /usr/games/steamcmd +force_install_dir $GAMEDIR/AppFiles +login anonymous +app_update 2430930 validate +quit
# STAGING TESTING - skip ark because it's huge
#sudo -u steam /usr/games/steamcmd +force_install_dir $GAMEDIR/AppFiles +login anonymous +app_update 90 validate +quit
if [ $? -ne 0 ]; then
	echo "Could not install ARK Survival Ascended Dedicated Server, exiting"
	exit 1
fi


# Install the systemd service files for ARK Survival Ascended Dedicated Server
for MAP in $GAMEMAPS; do
	if [ "$MAP" == "ark-island" ]; then
		DESC="Island"
		NAME="TheIsland_WP"
		MODS=""
		GAMEPORT=7701
		RCONPORT=27001
	elif [ "$MAP" == "ark-aberration" ]; then
		DESC="Aberration"
		NAME="Aberration_P"
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
		NAME="ScorchedEarth_P"
		MODS=""
		GAMEPORT=7704
		RCONPORT=27004
	elif [ "$MAP" == "ark-thecenter" ]; then
		DESC="TheCenter"
		NAME="TheCenter_P"
		MODS=""
		GAMEPORT=7705
		RCONPORT=27005
	fi

	cat > /etc/systemd/system/${MAP}.service <<EOF
[Unit]
Description=ARK Survival Ascended Dedicated Server (${DESC})
After=network.target

[Service]
Type=simple
LimitNOFILE=10000
User=steam
Group=steam
WorkingDirectory=$GAMEDIR/AppFiles/ShooterGame/Binaries/Win64
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
Environment="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAMDIR"
Environment="STEAM_COMPAT_DATA_PATH=$GAMECOMPATDIR"
# Check $GAMEDIR/services to adjust the CLI arguments
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
ExecStart=$PROTONBIN run ArkAscendedServer.exe ${NAME}?listen?SessionName="${COMMUNITYNAME} (${DESC})"?RCONPort=${RCONPORT} -port=${GAMEPORT} -servergamelog -mods=$MODS
EOF
    fi
done


# Create start/stop helpers for all maps
cat > $GAMEDIR/start_all.sh <<EOF
#!/bin/bash
#
# Start all ARK server maps that are enabled
GAMEMAPS="$GAMEMAPS"

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
	sudo -u steam /usr/games/steamcmd +force_install_dir $GAMEDIR/AppFiles +login anonymous +app_update 2430930 validate +quit
	if [ \$? -ne 0 ]; then
		echo "Game update failed, not starting"
		exit 1
	fi
}

if [ \$(ps aux | grep ArkAscendedServer.exe | wc -l) -le 1 ]; then
	update_game
else
	echo "Game server is already running, not updating"
fi

for MAP in \$GAMEMAPS; do
	if [ "\$(systemctl is-enabled \$MAP)" == "enabled" -a "\$(systemctl is-active \$MAP)" == "inactive" ]; then
		start_game \$MAP
	fi
done
EOF
chown steam:steam $GAMEDIR/start_all.sh
chmod +x $GAMEDIR/start_all.sh


cat > $GAMEDIR/stop_all.sh <<EOF
#!/bin/bash
#
# Stop all ARK server maps that are enabled
GAMEMAPS="$GAMEMAPS"

function stop_game {
	echo "Stopping game instance \$1..."
	sudo systemctl stop \$1
	echo "Waiting 10 seconds for threads to settle"
	for i in {0..9}; do
		echo -n '.'
	done
	# Check status real quick
	sudo systemctl status \$1 | grep Active
}

for MAP in \$GAMEMAPS; do
	if [ "\$(systemctl is-enabled \$MAP)" == "enabled" -a "\$(systemctl is-active \$MAP)" == "active" ]; then
		stop_game \$MAP
	fi
done
EOF
chown steam:steam $GAMEDIR/stop_all.sh
chmod +x $GAMEDIR/stop_all.sh


# Reload systemd to pick up the new service files
systemctl daemon-reload


############################################
## Security Configuration
############################################

# Configure firewall
[ -d "/etc/firewalld/services" ] || mkdir -p /etc/firewalld/services
cat > /etc/firewalld/services/ark-survival.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>ARK Survival Ascended</short>
  <description>ARK Survival Ascended game server</description>
  <port port="7701-7720" protocol="udp"/>
  <port port="27001-27020" protocol="tcp"/>
</service>
EOF
firewall-cmd --permanent --zone=public --add-service=ark-survival


############################################
## Post-Install Configuration
############################################

# Create some helpful links for the user.
[ -e "$GAMEDIR/services" ] || sudo -u steam mkdir -p "$GAMEDIR/services"
for MAP in $GAMEMAPS; do
	[ -h "$GAMEDIR/services/${MAP}.conf" ] || sudo -u steam ln -s /etc/systemd/system/${MAP}.service.d/override.conf "$GAMEDIR/services/${MAP}.conf"
done
[ -h "$GAMEDIR/GameUserSettings.ini" ] || sudo -u steam ln -s $GAMEDIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini "$GAMEDIR/GameUserSettings.ini"
[ -h "$GAMEDIR/Game.ini" ] || sudo -u steam ln -s $GAMEDIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/Game.ini "$GAMEDIR/Game.ini"
[ -h "$GAMEDIR/ShooterGame.log" ] || sudo -u steam ln -s $GAMEDIR/AppFiles/ShooterGame/Saved/Logs/ShooterGame.log "$GAMEDIR/ShooterGame.log"


echo "================================================================================"
echo "If everything went well, ARK Survival Ascended should be installed!"
echo ""
for MAP in $GAMEMAPS; do
	echo "? Enable game map ${MAP}? (y/N)"
	echo -n "> "
	read OPT
	if [ "$OPT" == "y" -o "$OPT" == "Y" ]; then
		systemctl enable $MAP
	else
		echo "Not enabling ${MAP}, you can always enable it in the future with 'sudo systemctl enable $MAP'"
	fi
	echo ""
done
echo ""
echo "To restart a map:      sudo systemctl restart NAME-OF-MAP"
echo "To start a map:        sudo systemctl start NAME-OF-MAP"
echo "To stop a map:         sudo systemctl stop NAME-OF-MAP"
echo "Game files:            $GAMEDIR/AppFiles/"
echo "Runtime configuration: $GAMEDIR/services/"
echo "Game log:              $GAMEDIR/ShooterGame.log"
echo "Game user settings:    $GAMEDIR/GameUserSettings.ini"
echo "To start all maps:     $GAMEDIR/start_all.sh"
echo "To stop all maps:      $GAMEDIR/stop_all.sh"
