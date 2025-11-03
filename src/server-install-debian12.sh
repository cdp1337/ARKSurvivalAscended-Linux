#!/bin/bash
#
# Install ARK Survival Ascended Dedicated Server
#
# Uses Glorious Eggroll's build of Proton
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
# @SOURCE  https://github.com/cdp1337/ARKSurvivalAscended-Linux
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
#
# F*** Nitrado
#
# Supports:
#   Debian 12, 13
#   Ubuntu 24.04
#
# Requirements:
#   None
#
# TRMM Custom Fields:
#   None
#
# Syntax:
#   OPT_RESET_PROTON=--reset-proton - Reset proton directories back to default
#   OPT_FORCE_REINSTALL=--force-reinstall - Force a reinstall of the game binaries, mods, and engine
#   OPT_UNINSTALL=--uninstall - Uninstall the game server
#   OPT_INSTALL_CUSTOM_MAP=--install-custom-map - Install a custom map (in addition to the defaults)
#
# Changelog:
#   20251102 - Add support for uninstalling the server and all data
#            - Refactor how options are handled in the management console
#            - Add support for backup/start/stop maps as arguments to the management console
#            - Add support for custom modded maps
#   20251101 - Add support for Nitrado and Official server save formats
#            - Fix for if mods library is missing
#            - Add support for customizing all player messages
#            - Add memory usage statistics to management console
#            - Cleanup and simplify startup reporting
#   20251019 - Add support for displaying the name of the mods installed
#            - Assist user with troubleshooting by displaying the log on failure to start
#            - Add backup/restore interface in management console
#            - Add wipe player data functionality in management console
#   20251016 - Add auto-updater checks
#            - Fix support for Debian 13
#            - Add Valguero map
#   20250620 - Fix $GAME_USER for non-standard installs - thanks techgo!
#            - Add Ragnarok support
#   20250525 - Fix excessive question marks in options
#            - Expand exception handling in RCON for more meaningful error messages
#            - Add checks to prevent changes while a game is running
#            - Auto-create steam .ssh directory for convenience
#            - Auto-create Game.ini for convenience
#   20250505 - Add backup and restore scripts
#   20250502 - Add checks for running out of memory
#            - Add timeout to RCON for a more responsive UI when there are problems
#            - Modify map start logic to watch for memory issues in the first minute
#            - Update table listing to be Markdown compliant
#   20250310 - Add support for Discord integration on start/stop
#   20250217 - Switch to Proton 9.22
#            - Add Astraeos map
#            - Add management script
#            - Add --reset-proton option
#            - Add --force-reinstall option
#            - Add service upgrade check (when changing Proton versions)
#   20250128 - Fix missing escape character
#   20241220 - Switch to UFW
#            - Add Extinction
#

############################################
## Parameter Configuration
############################################

INSTALLER_VERSION="v20251101"
# https://github.com/GloriousEggroll/proton-ge-custom
PROTON_VERSION="9-22"
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
# Steam ID of the game
STEAM_ID="2430930"
# List of game maps currently available
GAME_MAPS="ark-island ark-aberration ark-club ark-scorched ark-thecenter ark-extinction ark-astraeos ark-ragnarok ark-valguero"
# How many base maps are installed by default (needed for the custom map logic)
BASE_MAP_COUNT=9
# Range of game ports to enable in the firewall
PORT_GAME_START=7701
PORT_GAME_END=7709
PORT_RCON_START=27001
PORT_RCON_END=27009
PORT_CUSTOM_GAME=7801
PORT_CUSTOM_RCON=27101

# compile:argparse
# scriptlet:_common/require_root.sh
# scriptlet:proton/install.sh
# scriptlet:_common/get_firewall.sh
# scriptlet:steam/install-steamcmd.sh
# scriptlet:ufw/install.sh
# scriptlet:_common/firewall_allow.sh
# scriptlet:_common/random_password.sh



############################################
## Pre-exec Checks
############################################

# Allow for auto-update checks
if [ -n "$(which curl)" -a "${0:0:8}" != "/dev/fd/" ]; then
	echo "Checking Github for updates..."
	GITHUB_VERSION="$(curl -s -L 'https://api.github.com/repos/cdp1337/ARKSurvivalAscended-Linux/releases?per_page=1&page=1' | grep 'tag_name' | sed 's:.* "\(v[0-9]*\)",:\1:')"
	if [ -n "$GITHUB_VERSION" ]; then
		if [ "$GITHUB_VERSION" != "$INSTALLER_VERSION" ]; then
			echo "A new version of the installer is available!"
			read -p "Do you want to update the installer? (y/N): " -t 10 UPDATE
			case "$UPDATE" in
				[yY]*)
					curl -L https://raw.githubusercontent.com/cdp1337/ARKSurvivalAscended-Linux/refs/tags/${GITHUB_VERSION}/dist/server-install-debian12.sh \
						-o "$0"
					chmod +x "$0"
					exec "$0" "${@}"
					exit 0
					;;
				*)
					echo "Skipping update";;
			esac
		fi
	fi
fi


# This script can run on an existing server, but should not update the game if a map is actively running.
# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		RUNNING=1
	fi
done

if [ $RUNNING -eq 1 -a $OPT_RESET_PROTON -eq 1 ]; then
	echo "Game server is still running, proton reset CAN NOT PROCEED"
	exit 1
fi

if [ $RUNNING -eq 1 -a $OPT_FORCE_REINSTALL -eq 1 ]; then
	echo "Game server is still running, force reinstallation CAN NOT PROCEED"
	exit 1
fi

if [ $RUNNING -eq 1 -a $OPT_UNINSTALL -eq 1 ]; then
	echo "Game server is still running, uninstallation CAN NOT PROCEED"
	exit 1
fi

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


echo "================================================================================"
echo "         	  ARK Survival Ascended *unofficial* Installer $INSTALLER_VERSION"
echo ""


############################################
## Uninstallation
############################################
if [ $OPT_UNINSTALL -eq 1 ]; then
	echo "? This will remove all game binary content"
	echo -n "> (y/N): "
	read CONFIRM
	if [ "$CONFIRM" != "y" -a "$CONFIRM" != "Y" ]; then
		exit
	fi

	echo "? This will remove all player and map data"
	echo -n "> (y/N): "
	read CONFIRM
	if [ "$CONFIRM" != "y" -a "$CONFIRM" != "Y" ]; then
		exit
	fi

	echo "? This will remove all service registration files"
	echo -n "> (y/N): "
	read CONFIRM
	if [ "$CONFIRM" != "y" -a "$CONFIRM" != "Y" ]; then
		exit
	fi

	if [ -e "$GAME_DIR/backup.sh" ]; then
		echo "? Would you like to perform a backup before everything is wiped?"
		echo -n "> (y/N): "
		read CONFIRM
		if [ "$CONFIRM" == "y" -o "$CONFIRM" == "Y" ]; then
			$GAME_DIR/backup.sh
		fi
	fi

	echo "Removing proton prefixes"
	[ -e "$GAME_DIR/prefixes" ] && rm "$GAME_DIR/prefixes" -r

	echo "Removing service files"
	ls -1 "$GAME_DIR/services" | while read SERVICE; do
		SERVICE="${SERVICE:0:-5}"
		systemctl disable $SERVICE
		[ -h "$GAME_DIR/services/${SERVICE}.conf" ] && unlink "$GAME_DIR/services/${SERVICE}.conf"
		[ -e "/etc/systemd/system/${SERVICE}.service" ] && rm "/etc/systemd/system/${SERVICE}.service"
		[ -e "/etc/systemd/system/${SERVICE}.service.d" ] && rm -r "/etc/systemd/system/${SERVICE}.service.d"
	done
	[ -e "/etc/systemd/system/ark-updater.service" ] && rm "/etc/systemd/system/ark-updater.service"
	[ -e "$GAME_DIR/services" ] && rm "$GAME_DIR/services" -r

	echo "Removing application data"
	[ -e "$GAME_DIR/AppFiles" ] && rm -r "$GAME_DIR/AppFiles"

	echo "Removing management system"
	[ -h "$GAME_DIR/admins.txt" ] && unlink "$GAME_DIR/admins.txt"
	[ -h "$GAME_DIR/Game.ini" ] && unlink "$GAME_DIR/Game.ini"
	[ -h "$GAME_DIR/GameUserSettings.ini" ] && unlink "$GAME_DIR/GameUserSettings.ini"
	[ -h "$GAME_DIR/PlayersJoinNoCheckList.txt" ] && unlink "$GAME_DIR/PlayersJoinNoCheckList.txt"
	[ -h "$GAME_DIR/ShooterGame.log" ] && unlink "$GAME_DIR/ShooterGame.log"
	[ -e "$GAME_DIR/manage.py" ] && rm "$GAME_DIR/manage.py"
	[ -e "$GAME_DIR/backup.sh" ] && rm "$GAME_DIR/backup.sh"
	[ -e "$GAME_DIR/restore.sh" ] && rm "$GAME_DIR/restore.sh"
	[ -e "$GAME_DIR/start_all.sh" ] && rm "$GAME_DIR/start_all.sh"
	[ -e "$GAME_DIR/stop_all.sh" ] && rm "$GAME_DIR/stop_all.sh"
	[ -e "$GAME_DIR/update.sh" ] && rm "$GAME_DIR/update.sh"
	[ -e "$GAME_DIR/.venv" ] && rm "$GAME_DIR/.venv" -r

	exit
fi


############################################
## User Prompts (pre setup)
############################################

# Ask the user some information before installing.
if [ "$INSTALLTYPE" == "new" ]; then
	echo "? What is the community name of the server? (e.g. My Awesome ARK Server)"
	echo -n "> "
	read COMMUNITYNAME
	if [ "$COMMUNITYNAME" == "" ]; then
		COMMUNITYNAME="My Awesome ARK Server"
	fi
elif [ -e "$GAME_DIR/services/ark-island.conf" ]; then
	# To support custom maps, load the existing community name from the island map service file.
	COMMUNITYNAME="$(egrep '^ExecStart' "$GAME_DIR/services/ark-island.conf" | sed 's:.*SessionName="\([^"]*\) (.*:\1:')"
else
	COMMUNITYNAME="My Awesome ARK Server"
fi

# Support legacy vs newsave formats
# https://ark.wiki.gg/wiki/2023_official_server_save_files
# Legacy formats use individual files for each character whereas
# "new" formats save all characters along with the map.
echo ''
if [ "$INSTALLTYPE" == "new" ]; then
	echo "? Will you be migrating an existing Nitrado or Wildcard server? "
	echo "(answering yes will enable the new save format)"
	echo -n "> (y/N): "
	read NEWFORMAT
	if [ "$NEWFORMAT" == "y" -o "$NEWFORMAT" == "Y" ]; then
		NEWFORMAT=1
	else
		NEWFORMAT=0
	fi
elif [ -e "$GAME_DIR/services/ark-island.conf" ]; then
	if grep -q '-newsaveformat' "$GAME_DIR/services/ark-island.conf"; then
		echo "Using new save format for existing installation"
		NEWFORMAT=1
	else
		echo "Using legacy save format for existing installation"
		NEWFORMAT=0
	fi
else
	echo "Using legacy save format for existing installation"
	NEWFORMAT=0
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

if [ $OPT_INSTALL_CUSTOM_MAP -eq 1 ]; then
	echo ''
	echo "Please enter the Mod ID of the custom map to install."
	echo "This is also called 'Project ID' on Curseforge."
	echo -n "> : "
	read CUSTOM_MAP_ID

	if [ -z "$CUSTOM_MAP_ID" ]; then
		echo "No Mod ID specified, cannot continue with custom map installation."
		exit 1
	fi

	echo ''
	echo "Please enter the Map Name to install."
	echo "This is usually listed on the Curseforge description page."
	echo -n "> : "
	read CUSTOM_MAP_NAME

	if [ -z "$CUSTOM_MAP_NAME" ]; then
		echo "No Map Name specified, cannot continue with custom map installation."
		exit 1
	fi

	# Custom maps usually end in "_WP", so trim that for the description if it's set.
	if [ "${CUSTOM_MAP_NAME:${#CUSTOM_MAP_NAME}-3}" == "_WP" ]; then
		CUSTOM_MAP_DESC="${CUSTOM_MAP_NAME:0:${#CUSTOM_MAP_NAME}-3}"
	else
		CUSTOM_MAP_DESC="${CUSTOM_MAP_NAME}"
	fi

	CUSTOM_MAP_MAP="ark-$(echo "$CUSTOM_MAP_DESC" | tr '[:upper:]' '[:lower:]')"

	if [ -e "$GAME_DIR/services" ]; then
		C=$(ls "$GAME_DIR/services" -1 | wc -l)
		let "CUSTOM_MAP_PORT=$C-$BASE_MAP_COUNT+$PORT_CUSTOM_GAME"
		let "CUSTOM_RCON_PORT=$C-$BASE_MAP_COUNT+$PORT_CUSTOM_RCON"
	else
		CUSTOM_MAP_PORT=$PORT_CUSTOM_GAME
		CUSTOM_RCON_PORT=$PORT_CUSTOM_RCON
	fi

	# Add the custom map to the list of maps to install
	GAME_MAPS="$GAME_MAPS CUSTOM"
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
# Setup the ssh directory for ths steam user; this will save some steps later
# should the user want to access the files via SFTP.
[ -d "/home/$GAME_USER/.ssh" ] || mkdir -p "/home/$GAME_USER/.ssh"
[ -e "/home/$GAME_USER/.ssh/authorized_keys" ] || touch "/home/$GAME_USER/.ssh/authorized_keys"
chown -R $GAME_USER:$GAME_USER "/home/$GAME_USER/.ssh"
chmod 700 "/home/$GAME_USER/.ssh"
chmod 600 "/home/$GAME_USER/.ssh/authorized_keys"

# Preliminary requirements
apt install -y curl wget sudo python3-venv

if [ "$(get_enabled_firewall)" == "none" ]; then
	# No firewall installed, go ahead and install UFW
	install_ufw
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

## Release 2023.10.31 - Issue #8
# Preserve customizations to service file
for MAP in $GAME_MAPS; do
	if [ "$MAP" == "CUSTOM" ]; then
		MAP="$CUSTOM_MAP_MAP"
	fi

	# Ensure the override directory exists for the admin modifications to the CLI arguments.
	[ -e /etc/systemd/system/${MAP}.service.d ] || mkdir -p /etc/systemd/system/${MAP}.service.d

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
## Installer Save (for uninstalling/upgrading/etc)
############################################

if [ "${0:0:8}" == "/dev/fd/" ]; then
	# Script was dynamically loaded, save a copy for future reference
	echo "Saving installer script for future reference..."
	wget -O "$GAME_DIR/installer.sh" "https://raw.githubusercontent.com/cdp1337/ARKSurvivalAscended-Linux/refs/tags/${INSTALLER_VERSION}/dist/server-install-debian12.sh"
	chmod +x "$GAME_DIR/installer.sh"
fi


############################################
## Game Installation
############################################

if [ $OPT_FORCE_REINSTALL -eq 1 ]; then
	# An option to force-reinstall the game binary,
	# useful because occasionally Wildcard fraks something up with Steam
	# and the only way to fix it is to force a reinstall.
	if [ -e "$GAME_DIR/AppFiles/Engine" ]; then
		echo "Removing Engine..."
		rm -fr "$GAME_DIR/AppFiles/Engine"
	fi

	echo "Removing Manifest files..."
	rm -f "$GAME_DIR/AppFiles/Manifest_DebugFiles_Win64.txt"
	rm -f "$GAME_DIR/AppFiles/Manifest_NonUFSFiles_Win64.txt"
	rm -f "$GAME_DIR/AppFiles/Manifest_UFSFiles_Win64.txt"

	if [ -e "$GAME_DIR/AppFiles/ShooterGame/Binaries" ]; then
		echo "Removing ShooterGame binaries..."
		rm -fr "$GAME_DIR/AppFiles/ShooterGame/Binaries"
	fi
	if [ -e "$GAME_DIR/AppFiles/ShooterGame/Content" ]; then
		echo "Removing ShooterGame content..."
		rm -fr "$GAME_DIR/AppFiles/ShooterGame/Content"
	fi
	if [ -e "$GAME_DIR/AppFiles/ShooterGame/Plugins" ]; then
		echo "Removing ShooterGame plugins..."
		rm -fr "$GAME_DIR/AppFiles/ShooterGame/Plugins"
	fi

	if [ -e "$GAME_DIR/AppFiles/steamapps" ]; then
		echo "Removing Steam meta files..."
		rm -fr "$GAME_DIR/AppFiles/steamapps"
	fi
fi

# Admin pass, used on new installs and shared across all maps
if [ -e "$GAME_DIR/services/ark-island.conf" ]; then
	ADMIN_PASS="$(grep -Eo 'ServerAdminPassword=[^? ]*' "$GAME_DIR/services/ark-island.conf" | sed 's:ServerAdminPassword=::')"
else
	ADMIN_PASS="$(random_password)"
fi

# Install ARK Survival Ascended Dedicated
if [ $RUNNING -eq 1 ]; then
	echo "WARNING - One or more game servers are currently running, this script will not update the game files."
	echo "Skipping steam update"
else
	sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update $STEAM_ID validate +quit
    # STAGING / TESTING - skip ark because it's huge; AppID 90 is Team Fortress 1 (a tiny server useful for testing)
    #sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update 90 validate +quit
    if [ $? -ne 0 ]; then
    	echo "Could not install ARK Survival Ascended Dedicated Server, exiting" >&2
    	exit 1
    fi
fi

GAMEFLAGS="-servergamelog"
# https://ark.wiki.gg/wiki/2023_official_server_save_files
if [ $NEWFORMAT -eq 1 ]; then
	GAMEFLAGS="$GAMEFLAGS -newsaveformat -usestore"
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
	elif [ "$MAP" == "ark-astraeos" ]; then
		DESC="Astraeos"
		NAME="Astraeos_WP"
		MODS=""
		GAMEPORT=7707
		RCONPORT=27007
	elif [ "$MAP" == "ark-ragnarok" ]; then
		DESC="Ragnarok"
		NAME="Ragnarok_WP"
		MODS=""
		GAMEPORT=7708
		RCONPORT=27008
	elif [ "$MAP" == "ark-valguero" ]; then
		DESC="Valguero"
		NAME="Valguero_WP"
		MODS=""
		GAMEPORT=7709
		RCONPORT=27009
	elif [ "$MAP" == "CUSTOM" ]; then
		MAP="$CUSTOM_MAP_MAP"
		DESC="$CUSTOM_MAP_DESC"
		NAME="$CUSTOM_MAP_NAME"
		MODS="$CUSTOM_MAP_ID"
		GAMEPORT=$CUSTOM_MAP_PORT
		RCONPORT=$CUSTOM_RCON_PORT
	fi

	if [ "$MODS" != "" ]; then
		MODS_LINE="-mods=$MODS"
	else
		MODS_LINE=""
	fi


	# Install system service file to be loaded by systemd
	cat > /etc/systemd/system/${MAP}.service <<EOF
# script:ark-template.service
EOF

	if [ -e /etc/systemd/system/${MAP}.service.d/override.conf ]; then
		# Override exists, check if it needs upgraded
		CURRENT_PROTON_BIN="$(grep ExecStart /etc/systemd/system/${MAP}.service.d/override.conf | sed 's:^ExecStart=\([^ ]*\) .*:\1:')"
		if [ "$CURRENT_PROTON_BIN" != "$PROTON_BIN" ]; then
			# Proton binary has changed, update the override
			echo "Upgrading Proton binary for $MAP from $CURRENT_PROTON_BIN to $PROTON_BIN"
			sed -i "s:^ExecStart=[^ ]*:ExecStart=$PROTON_BIN:" /etc/systemd/system/${MAP}.service.d/override.conf
		fi
	else
		# Override does not exist yet, create boilerplate file.
		# This is the main file that the admin will use to modify CLI arguments,
		# so we do not want to overwrite their work if they have already modified it.
		cat > /etc/systemd/system/${MAP}.service.d/override.conf <<EOF
# script:ark-override-template.service
EOF
    fi

    # Set the owner of the override to steam so that user account can modify it.
    chown $GAME_USER:$GAME_USER /etc/systemd/system/${MAP}.service.d/override.conf

    if [ $OPT_RESET_PROTON -eq 1 -a -e $GAME_DIR/prefixes/$MAP ]; then
    	echo "Resetting proton prefix for $MAP"
    	rm $GAME_DIR/prefixes/$MAP -r
	fi

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
# script:ark-updater.service
EOF

cat > $GAME_DIR/update.sh <<EOF
# script:update.sh
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/update.sh
chmod +x $GAME_DIR/update.sh
systemctl daemon-reload
systemctl enable ark-updater


# As of v2025.11.02 this script has been ported to the management console.
# Create start/stop helpers for all maps
#cat > $GAME_DIR/start_all.sh <<EOF
## script:start_all.sh
#EOF
#chown $GAME_USER:$GAME_USER $GAME_DIR/start_all.sh
#chmod +x $GAME_DIR/start_all.sh


# As of v2025.11.02 this script has been ported to the management console.
#cat > $GAME_DIR/stop_all.sh <<EOF
## script:stop_all.sh
#EOF
#chown $GAME_USER:$GAME_USER $GAME_DIR/stop_all.sh
#chmod +x $GAME_DIR/stop_all.sh


# Install a management script
sudo -u $GAME_USER python3 -m venv $GAME_DIR/.venv
sudo -u $GAME_USER $GAME_DIR/.venv/bin/pip install rcon
cat > $GAME_DIR/manage.py <<EOF
# script:manage.py
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/manage.py
chmod +x $GAME_DIR/manage.py

cat > $GAME_DIR/backup.sh <<EOF
# script:backup.sh
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/backup.sh
chmod +x $GAME_DIR/backup.sh

cat > $GAME_DIR/restore.sh <<EOF
# script:restore.sh
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/restore.sh
chmod +x $GAME_DIR/restore.sh


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

# Ensure cluster and game resources exist
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/PlayersJoinNoCheckList.txt"
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/admins.txt"
if [ ! -e "$GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer" ]; then
	sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer"
fi
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/Game.ini"

############################################
## Security Configuration
############################################

firewall_allow --port "${PORT_GAME_START}:${PORT_GAME_END}" --udp
firewall_allow --port "${PORT_RCON_START}:${PORT_RCON_END}" --tcp
if [ "$MULTISERVER" -eq 1 -a "$ISPRIMARY" -eq 1 ]; then
	# Allow NFS access from secondary servers
	for IP in $SECONDARYIPS; do
		firewall_allow --port "111,2049" --tcp --zone internal --source $IP/32
		firewall_allow --port "111,2049" --udp --zone internal --source $IP/32
	done
fi
if [ $OPT_INSTALL_CUSTOM_MAP -eq 1 ]; then
	firewall_allow --port "$CUSTOM_MAP_PORT" --udp
	firewall_allow --port "$CUSTOM_RCON_PORT" --tcp
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
[ -e "$GAME_DIR/services" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/services"
for MAP in $GAME_MAPS; do
	if [ "$MAP" == "CUSTOM" ]; then
		MAP="$CUSTOM_MAP_MAP"
	fi
	[ -h "$GAME_DIR/services/${MAP}.conf" ] || sudo -u $GAME_USER ln -s /etc/systemd/system/${MAP}.service.d/override.conf "$GAME_DIR/services/${MAP}.conf"
done
[ -h "$GAME_DIR/GameUserSettings.ini" ] || sudo -u $GAME_USER ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini "$GAME_DIR/GameUserSettings.ini"
[ -h "$GAME_DIR/Game.ini" ] || sudo -u $GAME_USER ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/Game.ini "$GAME_DIR/Game.ini"
[ -h "$GAME_DIR/ShooterGame.log" ] || sudo -u $GAME_USER ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/Logs/ShooterGame.log "$GAME_DIR/ShooterGame.log"
[ -h "$GAME_DIR/PlayersJoinNoCheckList.txt" ] || sudo -u $GAME_USER ln -s "$WL_CLUSTER" "$GAME_DIR/PlayersJoinNoCheckList.txt"
[ -h "$GAME_DIR/admins.txt" ] || sudo -u $GAME_USER ln -s $GAME_DIR/AppFiles/ShooterGame/Saved/clusters/admins.txt "$GAME_DIR/admins.txt"


echo "================================================================================"
echo "If everything went well, ARK Survival Ascended should be installed!"
echo ""
echo "Game files:            $GAME_DIR/AppFiles/"
echo "Runtime configuration: $GAME_DIR/services/"
echo "Game log:              $GAME_DIR/ShooterGame.log"
echo "Game user settings:    $GAME_DIR/GameUserSettings.ini"
if [ "$WHITELIST" -eq 1 ]; then
	echo "Whitelist:             $GAME_DIR/PlayersJoinNoCheckList.txt"
fi
echo "Admin list:            $GAME_DIR/admin.txt"
echo ''
echo ''
echo 'Wanna stop by and chat? https://discord.gg/jyFsweECPb'
echo 'Have an issue or feature request? https://github.com/cdp1337/ARKSurvivalAscended-Linux/issues'
echo 'Help support this and other projects? https://ko-fi.com/bitsandbytes'
echo ''
echo ''
echo '! IMPORTANT !'
echo 'to manage the server, as root/sudo run the following utility'
echo "$GAME_DIR/manage.py"
