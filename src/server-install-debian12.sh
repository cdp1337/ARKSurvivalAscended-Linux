#!/bin/bash
#
# Install ARK Survival Ascended Dedicated Server
#
# Installs ARK Survival Ascended Dedicated Server on Debian/Ubuntu systems
#
# Uses Glorious Eggroll's build of Proton
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
# @SOURCE  https://github.com/cdp1337/ARKSurvivalAscended-Linux
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
# @WARLOCK-TITLE ARK Survival Ascended
# @WARLOCK-IMAGE images/asa-1920x1080.webp
# @WARLOCK-ICON images/ark-128x128.webp
# @WARLOCK-THUMBNAIL images/ark_460x215.webp
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
#   OPT_OVERRIDE_DIR=--dir=<string> - Use a custom installation directory instead of the default OPTIONAL
#   NONINTERACTIVE=--non-interactive - Run the installer in non-interactive mode (useful for scripted installs)
#   SKIP_FIREWALL=--skip-firewall - Skip installing/configuring the firewall
#   OPT_NEWFORMAT=--new-format - Use the new save format (Nitrado/Official server compatible) OPTIONAL
#   BRANCH=--branch=<str> - Use a specific branch of the management script repository DEFAULT=main
#
# Changelog:
#   20251219 - Add support for Lost Colony
#            - Add per-map options to disable downloads
#            - Re-add option editing from CLI
#            - Regression fix for Debian 12
#            - New Warlock features
#   20251207 - Support custom installation directory
#            - Add support for some custom usecases of the installer
#            - Bump Proton to 10.25
#            - Fix for more flexible support for game options
#            - Backport 74.24 Steam fix into legacy start/stop scripts
#            - Add support for --new-format as an argument to support Warlock
#            - Fix support for JoinedSessionName (ini uses lowercase keys)
#            - Support for Warlock management system
#   20251105 - Fix broken Steam library in update 74.24
#            - Add support for skipping firewall installation
#            - Add support for using completely custom session names
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

# https://github.com/GloriousEggroll/proton-ge-custom
PROTON_VERSION="10-34"
WARLOCK_GUID="0c2de651-ec30-d4ac-c53f-ebdb67398324"
GAME="ArkSurvivalAscended"
GAME_USER="steam"
GAME_DIR="/home/$GAME_USER/$GAME"
REPO="cdp1337/ARKSurvivalAscended-Linux"
DISCORD="https://discord.gg/jyFsweECPb"
FUNDING="https://ko-fi.com/bitsandbytes"
# List of game maps currently available (LEGACY SUPPORT ONLY)
GAME_MAPS="ark-island ark-aberration ark-club ark-scorched ark-thecenter ark-extinction ark-astraeos ark-ragnarok ark-valguero ark-lostcolony"

# compile:usage
# compile:argparse
# scriptlet:_common/require_root.sh
# scriptlet:proton/install.sh
# scriptlet:_common/get_firewall.sh
# scriptlet:steam/install-steamcmd.sh
# scriptlet:_common/firewall_install.sh
# scriptlet:_common/firewall_allow.sh
# scriptlet:_common/random_password.sh
# scriptlet:bz_eval_tui/prompt_text.sh
# scriptlet:bz_eval_tui/prompt_yn.sh
# scriptlet:bz_eval_tui/print_header.sh
# scriptlet:warlock/install_warlock_manager.sh
# scriptlet:xvfb/install.sh


## Handle NFS setup
#
function setup_nfs() {
	if [ "$MULTISERVER" -eq 1 ]; then
		if [ "$ISPRIMARY" -eq 1 ]; then
			apt install -y nfs-kernel-server nfs-common
		else
			apt install -y nfs-common
		fi

		# Enable / ensure enabled shared directory for multi-server support
		if [ "$ISPRIMARY" -eq 1 ]; then
			systemctl enable nfs-server
			for IP in $SECONDARYIPS; do
				# Ensure the cluster folder is shared with the various child servers
				if [ ! $(grep -q "Saved/clusters $IP" /etc/exports) ]; then
					echo "Adding $IP to NFS access for $GAME_DIR/AppFiles/ShooterGame/Saved/clusters"
					echo "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters $IP/32(rw,sync,no_subtree_check)" >> /etc/exports
				fi

				# Allow NFS access from secondary servers
				firewall_allow --port "111,2049" --tcp --zone internal --source $IP/32
				firewall_allow --port "111,2049" --udp --zone internal --source $IP/32
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
}

##
# Install the game server
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#   GAME_DESC    - Description of the game (for logging purposes)
#   GAME_SERVICE - Service name to install with Systemd
#   SAVE_DIR     - Directory to store game save files
#
function install_application() {
	# Create a "steam" user account
    # This will create the account with no password, so if you need to log in with this user,
    # run `sudo passwd steam` to set a password.
    if [ -z "$(getent passwd $GAME_USER)" ]; then
    	useradd -m -U $GAME_USER
    fi

    # Ensure the target directory exists and is owned by the game user
	if [ ! -d "$GAME_DIR" ]; then
		mkdir -p "$GAME_DIR"
		chown $GAME_USER:$GAME_USER "$GAME_DIR"
	fi

    # Preliminary requirements
    apt install -y curl sudo python3-venv

    # ASA API requires xvfb to run.
	install_xvfb

    if [ "$FIREWALL" == "1" ]; then
    	if [ "$(get_enabled_firewall)" == "none" ]; then
    		# No firewall installed, go ahead and install UFW
    		firewall_install
    	fi
    fi

    [ -e "$GAME_DIR/AppFiles" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles"
    [ -e "$GAME_DIR/Configs" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/Configs"
    [ -e "$GAME_DIR/Packages" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/Packages"
    [ -e "$GAME_DIR/Environments" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/Environments"

    # Setup the ssh directory for ths steam user; this will save some steps later
    # should the user want to access the files via SFTP.
    [ -d "/home/$GAME_USER/.ssh" ] || mkdir -p "/home/$GAME_USER/.ssh"
    [ -e "/home/$GAME_USER/.ssh/authorized_keys" ] || touch "/home/$GAME_USER/.ssh/authorized_keys"
    chown -R $GAME_USER:$GAME_USER "/home/$GAME_USER/.ssh"
    chmod 700 "/home/$GAME_USER/.ssh"
    chmod 600 "/home/$GAME_USER/.ssh/authorized_keys"

    # Install steam binary and steamcmd
    install_steamcmd

    # Run Steamcmd to ensure it's available; fixes the ERROR! Failed to install app '...' (Missing configuration) issue
    sudo -u $GAME_USER /usr/games/steamcmd +login anonymous +quit
    sleep 5

    # Install the management script
    install_warlock_manager "$REPO" "$BRANCH" 2.2.8

    # Grab Proton from Glorious Eggroll
    PROTON_PATH="$(install_proton "$PROTON_VERSION")/proton"
    "$GAME_DIR/manage.py" set-config "Default Proton Path" "${PROTON_PATH}"

    # Install installer (this script) for uninstallation or manual work
	download "https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/dist/server-install-debian12.sh" "$GAME_DIR/installer.sh"
	chmod +x "$GAME_DIR/installer.sh"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/installer.sh"

	# Register this application install with Warlock so it can be picked up by the web manager.
	if [ -n "$WARLOCK_GUID" ]; then
		[ -d "/var/lib/warlock" ] || mkdir -p "/var/lib/warlock"
		echo -n "$GAME_DIR" > "/var/lib/warlock/${WARLOCK_GUID}.app"
	fi
}

##
# Upgrade logic for 1.0 to 2.2 to handle migration of ENV and overrides
#
function upgrade_application_1_0() {
	local SERVICE_PATH
	local CLUSTER_ID
	CLUSTER_ID=""

	# Migrate existing service to new format
	# This gets overwrote by the manager, but is needed to tell the system that the service is here.
	if [ ! -e "$GAME_DIR/Environments" ]; then
		sudo -u $GAME_USER mkdir -p "$GAME_DIR/Environments"
		sudo -u $GAME_USER mkdir -p "$GAME_DIR/Migrations"

		for MAP in $GAME_MAPS; do
			SERVICE_PATH="/etc/systemd/system/${MAP}.service"

			# Export this configuration so the new system can re-obtain all the configuration values
			# This is important because v1 to v2.2 changed CLI parameters.
			"$GAME_DIR/manage.py" --service "$MAP" --get-configs > "$GAME_DIR/Migrations/${MAP}.configs-$(date +%Y%m%d%H%M%S).json"

			if [ -e "${SERVICE_PATH}.d/override.conf" ]; then
				# The map name is required in 2.2
				MAPNAME="$(egrep '^ExecStart' ${SERVICE_PATH}.d/override.conf | sed 's:.*\.exe \(.*\)?listen.*:\1:')"
				cat > "$GAME_DIR/Migrations/${MAP}.map-$(date +%Y%m%d%H%M%S).json" <<EOD
[{"option": "Map Name", "value": "$MAPNAME"}]
EOD
				if grep -q 'clusterid=' "${SERVICE_PATH}.d/override.conf"; then
					CLUSTER_ID="$(egrep '^ExecStart' "${SERVICE_PATH}.d/override.conf" | sed 's:.*clusterid=\([^ ]*\).*:\1:')"
				fi
			fi

			# Extract out current environment variables from the systemd file into their own dedicated file
			egrep '^Environment' "${SERVICE_PATH}" | sed 's:^Environment=::' | sed 's:"::g' > "$GAME_DIR/Environments/${MAP}.env"
			chown $GAME_USER:$GAME_USER "$GAME_DIR/Environments/${MAP}.env"
			# Trim out those envs now that they're not longer required
			cat "${SERVICE_PATH}" | egrep -v '^Environment=' > "${SERVICE_PATH}.new"
			mv "${SERVICE_PATH}.new" "${SERVICE_PATH}"

			[ -e "${SERVICE_PATH}.d/override.conf" ] && rm -fr "${SERVICE_PATH}.d/override.conf"
			[ -e "${SERVICE_PATH}.d" ] && rm -fr "${SERVICE_PATH}.d"
		done

		if [ "$CLUSTER_ID" != "" ] && ! egrep -q '^defaultclusterid' "$GAME_DIR/.settings.ini"; then
			# Application doesn't have a default cluster ID.
			# Technically not a requirement, but helpful to be set since the operator can easily create new services
			cat > "$GAME_DIR/Migrations/_app.cluster-$(date +%Y%m%d%H%M%S).json" <<EOD
[{"option": "Default Cluster ID", "value": "$CLUSTER_ID"}]
EOD
		fi
	fi
}

##
# Perform any steps necessary for upgrading an existing installation.
#
function upgrade_application() {
	print_header "Existing installation detected, performing upgrade"

	# Uncomment if you need this
	upgrade_application_1_0
}

##
# Perform any operations necessary after the dependency installation is complete.
#
# Generally this will use the management API to perform the actual installation.
#
function postinstall() {
	print_header "Performing postinstall"

	# First run setup
	$GAME_DIR/manage.py first-run
}

##
# Uninstall the game server
#
# Expects the following variables:
#   GAME_DIR     - Directory where the game is installed
#   GAME_SERVICE - Service name used with Systemd
#   SAVE_DIR     - Directory where game save files are stored
#
function uninstall_application() {
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
	[ -e "$GAME_DIR/.settings.ini" ] && rm "$GAME_DIR/.settings.ini"
	[ -e "$GAME_DIR/configs.yaml" ] && rm "$GAME_DIR/configs.yaml"

	if [ -n "$WARLOCK_GUID" ]; then
		echo "Removing Warlock registration"
		[ -e "/var/lib/warlock/$WARLOCK_GUID.app" ] && rm "/var/lib/warlock/$WARLOCK_GUID.app"
	fi
}

##
# Clear the game binaries
#
# Generally not needed, but may be helpful sometimes when Wildcard fraks something up with Steam
#
function clear_game_binaries() {
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
}

##
# Clear Proton prefix directories
#
# Useful in some edge cases to fix weird Proton issues.
#
function clear_proton_prefix() {
	if [ -e "$GAME_DIR/Environments" ]; then
    	# Check for existing service files to determine if the service is running.
    	# This is important to prevent conflicts with the installer trying to modify files while the service is running.
    	for envfile in "$GAME_DIR/Environments/"*.env; do
    		SERVICE=$(basename "$envfile" .env)
    		# If there are no services, this will just be '*.env'.
    		if [ "$SERVICE" != "*" ]; then
    			echo "Resetting proton prefix for $SERVICE"
				rm "$GAME_DIR/prefixes/$SERVICE" -r
    		fi
    	done
    fi
}

############################################
## Pre-exec Checks
############################################


# This script can run on an existing server, but should not update the game if a map is actively running.
# Check if any maps are running; do not update an actively running server.
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		echo "${MAP} is still running, cannot continue"
		exit 1
	fi
done

if [ -e "$GAME_DIR/Environments" ]; then
	# Check for existing service files to determine if the service is running.
	# This is important to prevent conflicts with the installer trying to modify files while the service is running.
	for envfile in "$GAME_DIR/Environments/"*.env; do
		SERVICE=$(basename "$envfile" .env)
		# If there are no services, this will just be '*.env'.
		if [ "$SERVICE" != "*" ]; then
			if systemctl -q is-active $SERVICE; then
				echo "$GAME_DESC service is currently running, please stop all instances before running this installer."
				echo "You can do this with: sudo systemctl stop $SERVICE"
				exit 1
			fi
		fi
	done
fi

if [ $OPT_UNINSTALL -eq 1 ]; then
	MODE="uninstall"
elif [ -e "$GAME_DIR/AppFiles" ]; then
	MODE="reinstall"
else
	# Default to install mode
	MODE="install"
fi

if [ -n "$OPT_OVERRIDE_DIR" ]; then
	# User requested to change the install dir!
	# This changes the GAME_DIR from the default location to wherever the user requested.
	if [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ] ; then
		# Check for existing installation directory based on Warlock registration
		GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
		if [ "$GAME_DIR" != "$OPT_OVERRIDE_DIR" ]; then
			echo "ERROR: $GAME_DESC already installed in $GAME_DIR, cannot override to $OPT_OVERRIDE_DIR" >&2
			echo "If you want to move the installation, please uninstall first and then re-install to the new location." >&2
			exit 1
		fi
	fi

	GAME_DIR="$OPT_OVERRIDE_DIR"
	echo "Using ${GAME_DIR} as the installation directory based on explicit argument"
elif [ -e "/var/lib/warlock/${WARLOCK_GUID}.app" ]; then
	# Check for existing installation directory based on service file
	GAME_DIR="$(cat "/var/lib/warlock/${WARLOCK_GUID}.app")"
	echo "Detected installation directory of ${GAME_DIR} based on service registration"
else
	echo "Using default installation directory of ${GAME_DIR}"
fi


echo "================================================================================"
echo "         	  ARK Survival Ascended *unofficial* Installer"
echo ""

# Operations needed to be performed during a new installation
if [ "$MODE" == "install" ]; then

	# Ask the user some information before installing.
	if [ $SKIP_FIREWALL -eq 1 ]; then
		echo "Firewall explictly disabled, skipping installation of a system firewall"
		FIREWALL=0
	elif prompt_yn -q --default-yes "Install system firewall?"; then
		FIREWALL=1
	else
		FIREWALL=0
	fi

	COMMUNITYNAME="$(prompt_text --default="My Awesome ARK Server" "? What is the community name of the server?")"
	JOINEDSESSIONNAME=$(prompt_yn --default-yes "? Include map names in instance name? e.g. My Awesome ARK Server (Island)")

	# Support legacy vs newsave formats
    # https://ark.wiki.gg/wiki/2023_official_server_save_files
    # Legacy formats use individual files for each character whereas
    # "new" formats save all characters along with the map.
	if [ $OPT_NEWFORMAT -eq 1 ]; then
    	echo "Using new save format for existing installation based on explicit argument"
    	NEWFORMAT=1
    else
      	echo "Nitrado and official servers are using a new save format"
      	echo "which combines all player data into the map save files."
      	echo ""
      	echo "If you plan on migrating existing content from those servers,"
      	echo "it is highly recommended to use the new save format."

      	NEWFORMAT=$(prompt_yn --default-yes "? Use new save format?")
	fi

	# Generate a cluster ID as users usually want to cluster their maps together
    CLUSTERID="$(random_password 12)"

	WHITELIST=$(prompt_yn --default-no "? Enable whitelist for players?")
	# Admin pass, used on new installs and shared across all maps
	ADMIN_PASS="$(random_password)"

	echo ''
	echo 'Multi-server support is provided via NFS by default,'
	echo 'but other file synchronization are possible if you prefer a custom solution.'
	echo ''
	echo 'This ONLY affects the default NFS, (do not enable if you are using a custom solution like VirtIO-FS or Gluster).'
	MULTISERVER=$(prompt_yn --default-no "? Enable multi-server NFS cluster support? (Maps spread across different servers)")

	if [ "$MULTISERVER" -eq 1 ]; then
		echo ''
		ISPRIMARY=$(prompt_yn --default-no "? Is this the first (primary) server?")

		if [ "$ISPRIMARY" -eq 1 ]; then
			echo ''
			SECONDARYIPS="$(prompt_text --default="" "? What are the IPs of the secondary servers? (Separate different IPs with spaces)")"
		else
			echo ''
			PRIMARYIP="$(prompt_text --default="" "? What is the IP of the primary server?")"
		fi
	fi

	install_application

	# Store the necessary arguments into the game system
	cat > "$GAME_DIR/Migrations/_app.initial-$(date +%Y%m%d%H%M%S).json" <<EOD
[
{"option": "Community Name", "value": "$COMMUNITYNAME"},
{"option": "Joined Session Name", "value": "$JOINEDSESSIONNAME"},
{"option": "Default New Save Format", "value": "$NEWFORMAT"},
{"option": "Default Cluster ID", "value": "$CLUSTERID"},
{"option": "Default Server Admin Password", "value": "$ADMIN_PASS"}
]
EOD

	# Handle NFS
	setup_nfs

	postinstall

	# Print some instructions and useful tips
    print_header "$GAME_DESC Installation Complete"
fi

# Operations needed to be performed during a reinstallation / upgrade
if [ "$MODE" == "reinstall" ]; then

	if [ $OPT_FORCE_REINSTALL -eq 1 ]; then
    	clear_game_binaries
    fi

    if [ $OPT_RESET_PROTON -eq 1 ]; then
    	clear_proton_prefix
	fi

	FIREWALL=0

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

    if [ "$MULTISERVER" -eq 1 ]; then
    	MULTISERVER=$(prompt_yn --invert --default-no "? DISABLE multi-server NFS cluster support? (Maps spread across different servers)")

    	if [ "$MULTISERVER" -eq 1 ] && [ "$ISPRIMARY" -eq 1 ]; then
    		echo ''
    		SECONDARYIPS="$(prompt_text --default="" "? Add more secondary IPs to the cluster? (Separate different IPs with spaces, enter to just skip)")"
    	fi
    fi

	upgrade_application

	install_application

	# Handle NFS
	setup_nfs

	postinstall

	# Print some instructions and useful tips
    print_header "$GAME_DESC Installation Complete"

	# If there are notes generated during installation, print them now.
    if [ -e "$GAME_DIR/Notes.txt" ]; then
    	cat "$GAME_DIR/Notes.txt"
	fi
fi

# Operations needed to be performed during an uninstallation
if [ "$MODE" == "uninstall" ]; then
	if [ $NONINTERACTIVE -eq 0 ]; then
		if prompt_yn -q --invert --default-no "This will remove all game binary content"; then
			exit 1
		fi
		if prompt_yn -q --invert --default-no "This will remove all player and map data"; then
			exit 1
		fi
	fi

	if prompt_yn -q --default-yes "Perform a backup before everything is wiped?"; then
		$GAME_DIR/manage.py backup
	fi

	uninstall_application
fi


############################################
## Game Installation
############################################

# Ensure cluster resources exist
[ -d "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters" ] || sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters"

# Ensure cluster and game resources exist
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/PlayersJoinNoCheckList.txt"
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/admins.txt"
if [ ! -e "$GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer" ]; then
	sudo -u $GAME_USER mkdir -p "$GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer"
fi
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/Config/WindowsServer/Game.ini"


############################################
## Post-Install Configuration
############################################


# Setup whitelist
WL_GAME="$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64/PlayersJoinNoCheckList.txt"
WL_CLUSTER="$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/PlayersJoinNoCheckList.txt"
if [ -e "$WL_GAME" ] && [ ! -h "$WL_GAME" ]; then
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
if [ -n "$DISCORD" ]; then
	echo "Wanna stop by and chat? ${DISCORD}"
fi
if [ -n "$REPO" ]; then
	echo "Have an issue or feature request? https://github.com/${REPO}/issues"
fi
if [ -n "$FUNDING" ]; then
	echo "Help support this and other projects? ${FUNDING}"
fi
echo ''
echo ''
echo '! IMPORTANT !'
echo 'to manage the server, as root/sudo run the following utility'
echo "$GAME_DIR/manage.py"
