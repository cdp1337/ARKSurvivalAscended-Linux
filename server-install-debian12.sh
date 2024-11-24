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

# Only allow running as root
if [ "$LOGNAME" != "root" ]; then
	echo "Please run this script as root! (If you ran with 'su', use 'su -' instead)" >&2
	exit 1
fi


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


# We will use this directory as a working directory for source files that need downloaded.
[ -d /opt/game-resources ] || mkdir -p /opt/game-resources


# Preliminary requirements
dpkg --add-architecture i386
apt update
apt install -y software-properties-common apt-transport-https dirmngr ca-certificates curl wget sudo


# Enable "non-free" repos for Debian (for steamcmd)
#add-apt-repository -y -c 'contrib'
#add-apt-repository -y -c 'non-free-firmware'
# https://stackoverflow.com/questions/76688863/apt-add-repository-doesnt-work-on-debian-12
add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free


# Install steam repo
curl -s http://repo.steampowered.com/steam/archive/stable/steam.gpg > /usr/share/keyrings/steam.gpg
echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] http://repo.steampowered.com/steam/ stable steam" > /etc/apt/sources.list.d/steam.list


# Install steam binary and steamcmd
apt update
apt install -y lib32gcc-s1 steamcmd


# Grab Proton from Glorious Eggroll
# https://github.com/GloriousEggroll/proton-ge-custom
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-20/GE-Proton9-20.tar.gz"
PROTON_TGZ="$(basename "$PROTON_URL")"
PROTON_NAME="$(basename "$PROTON_TGZ" ".tar.gz")"
if [ ! -e "/opt/game-resources/$PROTON_TGZ" ]; then
	wget "$PROTON_URL" -O "/opt/game-resources/$PROTON_TGZ"
fi


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


# Create a "steam" user account
# This will create the account with no password, so if you need to log in with this user,
# run `sudo passwd steam` to set a password.
[ -d /home/steam ] || useradd -m -U steam


# Install ARK Survival Ascended Dedicated
sudo -u steam /usr/games/steamcmd +force_install_dir $GAMEDIR/AppFiles +login anonymous +app_update 2430930 validate +quit


# Extract GE Proton into this user's Steam path
[ -d "$COMPATDIR" ] || sudo -u steam mkdir -p "$COMPATDIR"
sudo -u steam tar -x -C "$COMPATDIR/" -f "/opt/game-resources/$PROTON_TGZ"


# Install default prefix into game compatdata path
[ -d "$STEAMDIR/steamapps/compatdata" ] || sudo -u steam mkdir -p "$STEAMDIR/steamapps/compatdata"
[ -d "$STEAMDIR/steamapps/compatdata/2430930" ] || \
  sudo -u steam cp "$STEAMDIR/compatibilitytools.d/$PROTON_NAME/files/share/default_pfx" "$STEAMDIR/steamapps/compatdata/2430930" -r




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


# Install the systemd service files for ARK Survival Ascended Dedicated Server
for MAP in $GAMEMAPS; do
	if [ "$MAP" -eq "ark-island" ]; then
		DESC="Island"
		NAME="TheIsland_WP"
		GAMEPORT=7701
		RCONPORT=27001
	elif [ "$MAP" -eq "ark-aberration" ]; then
		DESC="Aberration"
		NAME="Aberration_P"
		GAMEPORT=7702
		RCONPORT=27002
	elif [ "$MAP" -eq "ark-club" ]; then
		DESC="Club"
		NAME="Club_P"
		GAMEPORT=7703
		RCONPORT=27003
	elif [ "$MAP" -eq "ark-scorched" ]; then
		DESC="Scorched"
		NAME="ScorchedEarth_P"
		GAMEPORT=7704
		RCONPORT=27004
	elif [ "$MAP" -eq "ark-thecenter" ]; then
		DESC="TheCenter"
		NAME="TheCenter_P"
		GAMEPORT=7705
		RCONPORT=27005
	fi

	cat > /etc/systemd/system/${MAP}.service <<EOF
[Unit]
Description=ARK Survival Ascended Dedicated Server $DESC
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
# Check /home/steam/ArkSurvivalAscended/services to adjust the CLI arguments
ExecStart=/bin/false
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
ExecStart=$PROTONBIN run ArkAscendedServer.exe ${NAME}?listen?SessionName="${COMMUNITYNAME} (${DESC})"?RCONPort=${RCONPORT} -port=${GAMEPORT}
EOF
    fi
done




systemctl daemon-reload
#systemctl enable ark-island
#systemctl start ark-island


# Create some helpful links for the user.
[ -e "/home/steam/island-GameUserSettings.ini" ] || \
  sudo -u steam ln -s "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" /home/steam/island-GameUserSettings.ini

[ -e "/home/steam/island-ShooterGame.log" ] || \
  sudo -u steam ln -s "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Logs/ShooterGame.log" /home/steam/island-ShooterGame.log

echo "================================================================================"
echo "If everything went well, ARK Survival Ascended should be installed and starting!"
echo ""
echo "To restart the server: sudo systemctl restart ark-island"
echo "To start the server:   sudo systemctl start ark-island"
echo "To stop the server:    sudo systemctl stop ark-island"
echo ""
echo "Configuration is available in /home/steam/island-GameUserSettings.ini"
