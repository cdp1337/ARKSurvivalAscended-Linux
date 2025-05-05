#!/bin/bash
#
# Install ARK Survival Ascended Dedicated Server
#
# Uses Glorious Eggroll's build of Proton
# Please ensure to run this script as root (or at least with sudo)
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@veraciousnetwork.com>
# @SOURCE  https://github.com/cdp1337/ARKSurvivalAscended-Linux
# @CATEGORY Game Server
# @TRMM-TIMEOUT 600
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
# Syntax:
#   --reset-proton - Reset proton directories back to default
#   --force-reinstall - Force a reinstall of the game binaries, mods, and engine
#
# Changelog:
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
GAME_MAPS="ark-island ark-aberration ark-club ark-scorched ark-thecenter ark-extinction ark-astraeos"
# Range of game ports to enable in the firewall
PORT_GAME_START=7701
PORT_GAME_END=7707
PORT_RCON_START=27001
PORT_RCON_END=27007

# Parse arguments
OPT_RESET_PROTON=0
OPT_FORCE_REINSTALL=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--reset-proton) OPT_RESET_PROTON=1; shift 1;;
		--force-reinstall) OPT_FORCE_REINSTALL=1; shift 1;;
	esac
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi
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

##
# Get which firewall is available on the local system,
# or "none" if none located
function get_available_firewall() {
	if systemctl list-unit-files firewalld.service &>/dev/null; then
		echo "firewalld"
	elif systemctl list-unit-files ufw.service &>/dev/null; then
		echo "ufw"
	elif systemctl list-unit-files iptables.service &>/dev/null; then
		echo "iptables"
	else
		echo "none"
	fi
}
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

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_bsd() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		echo 1
	else
		echo 0
	fi
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
function os_like_macos() {
	if [ "$(uname -s)" == 'Darwin' ]; then
		echo 1
	else
		echo 0
	fi
}

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

##
# Install a package with the system's package manager.
#
# Uses Redhat's yum, Debian's apt-get, and SuSE's zypper.
#
# Usage:
#
# ```syntax-shell
# package_install apache2 php7.0 mariadb-server
# ```
#
# @param $1..$N string
#        Package, (or packages), to install.  Accepts multiple packages at once.
#
function package_install (){
	echo "package_install: Installing $*..."

	TYPE_BSD="$(os_like_bsd)"
	TYPE_DEBIAN="$(os_like_debian)"
	TYPE_RHEL="$(os_like_rhel)"
	TYPE_ARCH="$(os_like_arch)"
	TYPE_SUSE="$(os_like_suse)"

	if [ "$TYPE_BSD" == 1 ]; then
		pkg install -y $*
	elif [ "$TYPE_DEBIAN" == 1 ]; then
		apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
	elif [ "$TYPE_RHEL" == 1 ]; then
		yum install -y $*
	elif [ "$TYPE_ARCH" == 1 ]; then
		pacman -Syu --noconfirm $*
	elif [ "$TYPE_SUSE" == 1 ]; then
		zypper install -y $*
	else
		echo 'package_install: Unsupported or unknown OS' >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		exit 1
	fi
}

##
# Install UFW
#
function install_ufw() {
	if [ "$(os_like_rhel)" == 1 ]; then
		# RHEL/CentOS requires EPEL to be installed first
		package_install epel-release
	fi

	package_install ufw

	# Auto-enable a newly installed firewall
	ufw --force enable
	systemctl enable ufw
	systemctl start ufw

	# Auto-add the current user's remote IP to the whitelist (anti-lockout rule)
	local TTY_IP="$(who am i | awk '{print $5}' | sed 's/[()]//g')"
	if [ -n "$TTY_IP" ]; then
		ufw allow from $TTY_IP comment 'Anti-lockout rule based on first install of UFW'
	fi
}
##
# Add an "allow" rule to the firewall in the INPUT chain
#
# Arguments:
#   --port <port>       Port(s) to allow
#   --source <source>   Source IP to allow (default: any)
#   --zone <zone>       Zone to allow (default: public)
#   --tcp|--udp         Protocol to allow (default: tcp)
#   --comment <comment> (only UFW) Comment for the rule
#
# Specify multiple ports with `--port '#,#,#'` or a range `--port '#:#'`
function firewall_allow() {
	# Defaults and argument processing
	local PORT=""
	local PROTO="tcp"
	local SOURCE="any"
	local FIREWALL=$(get_available_firewall)
	local ZONE="public"
	local COMMENT=""
	while [ $# -ge 1 ]; do
		case $1 in
			--port)
				shift
				PORT=$1
				;;
			--tcp|--udp)
				PROTO=${1:2}
				;;
			--source|--from)
				shift
				SOURCE=$1
				;;
			--zone)
				shift
				ZONE=$1
				;;
			--comment)
				shift
				COMMENT=$1
				;;
			*)
				PORT=$1
				;;
		esac
		shift
	done

	if [ "$PORT" == "" -a "$ZONE" != "trusted" ]; then
		echo "firewall_allow: No port specified!" >&2
		exit 1
	fi

	if [ "$PORT" != "" -a "$ZONE" == "trusted" ]; then
		echo "firewall_allow: Trusted zones do not use ports!" >&2
		exit 1
	fi

	if [ "$ZONE" == "trusted" -a "$SOURCE" == "any" ]; then
		echo "firewall_allow: Trusted zones require a source!" >&2
		exit 1
	fi

	if [ "$FIREWALL" == "ufw" ]; then
		if [ "$SOURCE" == "any" ]; then
			echo "firewall_allow/UFW: Allowing $PORT/$PROTO from any..."
			ufw allow proto $PROTO to any port $PORT comment "$COMMENT"
		elif [ "$ZONE" == "trusted" ]; then
			echo "firewall_allow/UFW: Allowing all connections from $SOURCE..."
			ufw allow from $SOURCE comment "$COMMENT"
		else
			echo "firewall_allow/UFW: Allowing $PORT/$PROTO from $SOURCE..."
			ufw allow from $SOURCE proto $PROTO to any port $PORT comment "$COMMENT"
		fi
	elif [ "$FIREWALL" == "firewalld" ]; then
		if [ "$SOURCE" != "any" ]; then
			# Firewalld uses Zones to specify sources
			echo "firewall_allow/firewalld: Adding $SOURCE to $ZONE zone..."
			firewall-cmd --zone=$ZONE --add-source=$SOURCE --permanent
		fi

		if [ "$PORT" != "" ]; then
			echo "firewall_allow/firewalld: Allowing $PORT/$PROTO in $ZONE zone..."
			if [[ "$PORT" =~ ":" ]]; then
				# firewalld expects port ranges to be in the format of "#-#" vs "#:#"
				local DPORTS="${PORT/:/-}"
				firewall-cmd --zone=$ZONE --add-port=$DPORTS/$PROTO --permanent
			elif [[ "$PORT" =~ "," ]]; then
				# Firewalld cannot handle multiple ports all that well, so split them by the comma
				# and run the add command separately for each port
				local DPORTS="$(echo $PORT | sed 's:,: :g')"
				for P in $DPORTS; do
					firewall-cmd --zone=$ZONE --add-port=$P/$PROTO --permanent
				done
			else
				firewall-cmd --zone=$ZONE --add-port=$PORT/$PROTO --permanent
			fi
		fi

		firewall-cmd --reload
	elif [ "$FIREWALL" == "iptables" ]; then
		echo "firewall_allow/iptables: WARNING - iptables is untested"
		# iptables doesn't natively support multiple ports, so we have to get creative
		if [[ "$PORT" =~ ":" ]]; then
			local DPORTS="-m multiport --dports $PORT"
		elif [[ "$PORT" =~ "," ]]; then
			local DPORTS="-m multiport --dports $PORT"
		else
			local DPORTS="--dport $PORT"
		fi

		if [ "$SOURCE" == "any" ]; then
			echo "firewall_allow/iptables: Allowing $PORT/$PROTO from any..."
			iptables -A INPUT -p $PROTO $DPORTS -j ACCEPT
		else
			echo "firewall_allow/iptables: Allowing $PORT/$PROTO from $SOURCE..."
			iptables -A INPUT -p $PROTO $DPORTS -s $SOURCE -j ACCEPT
		fi
		iptables-save > /etc/iptables/rules.v4
	elif [ "$FIREWALL" == "none" ]; then
		echo "firewall_allow: No firewall detected" >&2
		exit 1
	else
		echo "firewall_allow: Unsupported or unknown firewall" >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		exit 1
	fi
}
##
# Generate a random password, (using characters that are easy to read and type)
function random_password() {
	< /dev/urandom tr -dc _cdefhjkmnprtvwxyACDEFGHJKLMNPQRTUVWXY2345689 | head -c${1:-24};echo;
}


############################################
## Pre-exec Checks
############################################

# This script can run on an existing server, but should not update the game if a map is actively running.
# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		RUNNING=1
	fi
done

if [ $RUNNING -eq 1 -a $OPT_RESET_PROTON -eq 1 ]; then
	echo "Game server is still running, force reinstallation CAN NOT PROCEED"
	exit 1
fi

if [ $RUNNING -eq 1 -a $OPT_FORCE_REINSTALL -eq 1 ]; then
	echo "Game server is still running, force reinstallation CAN NOT PROCEED"
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
ADMIN_PASS="$(random_password)"

# Install ARK Survival Ascended Dedicated
if [ $RUNNING -eq 1 ]; then
	echo "WARNING - One or more game servers are currently running, this script will not update the game files."
	echo "Skipping steam update"
else
	sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update $STEAM_ID validate +quit
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
	elif [ "$MAP" == "ark-astraeos" ]; then
		DESC="Astraeos"
		NAME="Astraeos_WP"
		MODS=""
		GAMEPORT=7707
		RCONPORT=27007
	fi

	if [ "$MODS" != "" ]; then
		MODS_LINE="-mods=$MODS"
	else
		MODS_LINE=""
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
[Service]
# Edit this line to adjust start parameters of the server
# After modifying, please remember to run `sudo systemctl daemon-reload` to apply changes to the system.
ExecStart=$PROTON_BIN run ArkAscendedServer.exe ${NAME}?listen?SessionName="${COMMUNITYNAME} (${DESC})"?RCONPort=${RCONPORT}?ServerAdminPassword=${ADMIN_PASS}?RCONEnabled=True -port=${GAMEPORT} -servergamelog ${MODS_LINE}
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
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
STEAM_ID="$STEAM_ID"

# This script is expected to be run as the steam user, (as that is the owner of the game files).
# If another user calls this script, sudo will be used to switch to the steam user.
if [ "\$(whoami)" == "\$GAME_USER" ]; then
	SUDO_NEEDED=0
else
	SUDO_NEEDED=1
fi

function update_game {
	echo "Running game update"
	if [ "\$SUDO_NEEDED" -eq 1 ]; then
		sudo -u \$GAME_USER /usr/games/steamcmd +force_install_dir \$GAME_DIR/AppFiles +login anonymous +app_update \$STEAM_ID validate +quit
	else
		/usr/games/steamcmd +force_install_dir \$GAME_DIR/AppFiles +login anonymous +app_update \$STEAM_ID validate +quit
	fi

	if [ \$? -ne 0 ]; then
		echo "Game update failed!" >&2
		exit 1
	fi
}

# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-active \$MAP)" == "active" ]; then
		echo "WARNING - \$MAP is still running"
		RUNNING=1
	fi
done

if [ \$RUNNING -eq 1 ]; then
	echo "At least one map is still running, do you still want to run updates? (y/N): "
	read UP
	if [ "\$UP" == "y" -o "\$UP" == "Y" ]; then
		RUNNING=0
	fi
fi

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
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
STEAM_ID="$STEAM_ID"

function start_game {
	echo "Starting game instance \$1..."
	sudo systemctl start \$1
	echo "Waiting 30 seconds for threads to start"
	for i in {0..9}; do
		sleep 3
		echo -n '.'
	done
	# Check status real quick
	sudo systemctl status \$1 | grep Active
}

function update_game {
	echo "Running game update"
	sudo -u \$GAME_USER /usr/games/steamcmd +force_install_dir \$GAME_DIR/AppFiles +login anonymous +app_update \$STEAM_ID validate +quit
	if [ \$? -ne 0 ]; then
		echo "Game update failed, not starting"
		exit 1
	fi
}

RUNNING=0
for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-active \$MAP)" == "active" ]; then
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


# Install a management script
sudo -u $GAME_USER python3 -m venv $GAME_DIR/.venv
sudo -u $GAME_USER $GAME_DIR/.venv/bin/pip install rcon
cat > $GAME_DIR/manage.py <<EOF
#!/usr/bin/env python3

import os
import sys
from time import sleep
from typing import Union

here = os.path.dirname(os.path.realpath(__file__))
if not os.path.exists(os.path.join(here, '.venv')):
	print('Python environment not setup')
	exit(1)
sys.path.insert(
	0,
	os.path.join(
		here,
		'.venv',
		'lib',
		'python' + '.'.join(sys.version.split('.')[:2]), 'site-packages'
	)
)
#sys.path.insert(0, os.path.join(here, 'libs'))

import subprocess
import readline
import re
from rcon.source import Client
from rcon import SessionTimeout
import configparser
from urllib import request
from urllib import error as urlerror
import json


# Require sudo / root to run this script
if os.geteuid() != 0:
	print("This script must be run as root")
	sys.exit(1)


def rlinput(prompt, prefill=''):
	"""
	Use Readline to read input with a pre-filled value that can be edited by the user
	:param prompt:
	:param prefill:
	:return:
	"""
	readline.set_startup_hook(lambda: readline.insert_text(prefill))
	try:
		return input(prompt)  # or raw_input in Python 2
	finally:
		readline.set_startup_hook()


def discord_message(message: str) -> str:
	"""
	Get the user-defined message to be sent to Discord, or default if not configured.
	:param message:
	:return:
	"""
	messages = {
		'map_started': ':green_square: %s has started',
		'maps_stopping': ':small_red_triangle_down: Shutting down: %s',
		'map_stopping': ':small_red_triangle_down: %s shutting down',
	}
	if message in messages:
		# Check if there is a configured value
		configured_message = config['Discord'].get(message, '')
		if configured_message == '':
			# No configured message, use default.
			message = messages[message]
		else:
			message = configured_message

	return message


def discord_alert(message: str, parameters: list):
	enabled = config['Discord'].get('enabled', '0') == '1'
	webhook = config['Discord'].get('webhook', '')
	message = discord_message(message)

	# Verify the number of '%s' replacements in the string
	# This is important because this is a user-definable string, and users may forget to include '%s'.
	if message.count('%s') < len(parameters):
		message = message + ' %s' * (len(parameters) - message.count('%s'))
	message = message % tuple(parameters)

	if enabled and webhook != '':
		print('Sending to discord: ' + message)
		req = request.Request(
			webhook,
			headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0'},
			method='POST'
		)
		data = json.dumps({'content': message}).encode('utf-8')
		try:
			with request.urlopen(req, data=data) as resp:
				pass
		except urlerror.HTTPError as e:
			print('Could not notify Discord: %s' % e)
	else:
		print('Would be sent to discord: ' + message)


class Services:
	"""
	Service definition and handler
	"""
	def __init__(self, file):
		"""
		Initialize and load the service definition
		:param file:
		"""
		self.file = file
		self.name = file.split('/')[-1].replace('.conf', '')
		with open(self.file, 'r') as f:
			for line in f.readlines():
				if not line.startswith('ExecStart='):
					continue

				# Extract out all the various info from the start line
				extracted_keys = re.match(
					(r'ExecStart=(?P<runner>[^ ]*) run ArkAscendedServer.exe' 
					 r'(?P<map>[^/?]*)\?listen\?SessionName="(?P<session>[^"]*)"'
					 r'\?(?P<options>[^ ]*) (?P<flags>.*)'
					),
					line
				)

				self.runner = extracted_keys.group('runner')
				self.map = extracted_keys.group('map').strip()
				self.session = extracted_keys.group('session')
				self.rcon = None
				self.rcon_enabled = None
				self.admin_password = None
				self.port = None
				self.mods = []
				self.cluster_id = None
				self.other_options = ''
				self.other_flags = ''

				options = extracted_keys.group('options').split('?')
				flags = extracted_keys.group('flags').split(' ')

				for option in options:
					if option.startswith('RCONPort='):
						self.rcon = option[9:]
					elif option.startswith('RCONEnabled='):
						self.rcon_enabled = option[12:] == 'True'
					elif option.startswith('ServerAdminPassword='):
						self.admin_password = option[20:]
					else:
						self.other_options += option + '?'

				for flag in flags:
					if flag.startswith('-port='):
						self.port = flag[6:]
					elif flag.startswith('-mods='):
						if ',' in flag:
							self.mods += flag[6:].split(',')
						else:
							self.mods.append(flag[6:])
					elif flag.startswith('-clusterid='):
						self.cluster_id = flag[11:]
					else:
						self.other_flags += flag + ' '

				# Try to load some info from ini if necessary
				ini_file = os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Config', 'WindowsServer', 'GameUserSettings.ini')
				if os.path.exists(ini_file):
					with open(ini_file, 'r') as ini:
						for line in ini.readlines():
							if self.admin_password is None and line.startswith('ServerAdminPassword='):
								self.admin_password = line[20:].strip()
							if self.rcon_enabled is None and line.startswith('RCONEnabled='):
								self.rcon_enabled = line[12:].strip() == 'True'

	def save(self):
		"""
		Save the service definition back to the service file
		and reload systemd with the new updates.
		:return:
		"""
		options = '?'.join([
			self.map,
			'listen',
			'SessionName="%s"' % self.session,
			'RCONPort=%s' % self.rcon
		])
		if self.admin_password:
			options += '?ServerAdminPassword=%s' % self.admin_password
		if self.rcon_enabled is not None:
			options += '?RCONEnabled=%s' % ('True' if self.rcon_enabled else 'False')
		if self.other_options:
			options += '?' + self.other_options

		flags = '-port=%s' % self.port

		if len(self.mods):
			flags += ' -mods=%s' % ','.join(self.mods)
		if self.cluster_id:
			flags += ' -clusterid=%s' % self.cluster_id
		if self.other_flags:
			flags += ' ' + self.other_flags

		line = 'ExecStart=%s run ArkAscendedServer.exe %s %s' % (self.runner, options, flags)

		# Save the compiled line back to the service file, (along with the header)
		with open(self.file, 'w') as f:
			f.write('[Service]\n')
			f.write('# Edit this line to adjust start parameters of the server\n')
			f.write('# After modifying, please remember to run  to apply changes to the system.\n')
			f.write(line + '\n')

		# Reload the service
		subprocess.run(['systemctl', 'daemon-reload'])

	def _rcon_cmd(self, cmd) -> Union[None,str]:
		"""
		Execute a raw command with RCON and return the result

		:param cmd:
		:return: None if RCON not available, or the result of the command
		"""
		if not self.is_running():
			# If service is not running, don't even try to connect.
			return None

		if not self.admin_password:
			# No admin password set, unable to retrieve any data
			return None

		try:
			with Client('127.0.0.1', int(self.rcon), passwd=self.admin_password, timeout=2) as client:
				return client.run(cmd).strip()
		except (ConnectionRefusedError, ConnectionResetError, SessionTimeout, TimeoutError):
			return None

	def rcon_get_number_players(self) -> Union[None, int]:
		"""
		Get the total number of players currently logged in,
		or None if RCON is not available
		:return:
		"""
		ret =  self._rcon_cmd('ListPlayers')
		if ret is None:
			return None
		elif ret == 'No Players Connected':
			return 0
		else:
			return len(ret.split('\n'))

	def rcon_save_world(self):
		"""
		Issue a Save command on the server
		:return:
		"""
		self._rcon_cmd('SaveWorld')

	def rcon_message(self, message: str):
		"""
		Send a message to the game server
		:param message:
		:return:
		"""
		self._rcon_cmd('ServerChat %s' % message)

	def rename(self, new_name):
		"""
		Rename the session name
		:param new_name:
		:return:
		"""
		if '(' in self.session:
			self.session = new_name.replace('"', '') + ' ' + self.session[self.session.index('('):]
		else:
			self.session = new_name.replace('"', '')
		self.save()

	def is_enabled(self) -> bool:
		"""
		Check if this service is enabled in systemd
		:return:
		"""
		return subprocess.run(
			['systemctl', 'is-enabled', self.name],
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE,
			check=False
		).stdout.decode().strip() == 'enabled'

	def is_running(self) -> bool:
		"""
		Check if this service is currently running
		:return:
		"""
		return subprocess.run(
			['systemctl', 'is-active', self.name],
			stdout=subprocess.PIPE
		).stdout.decode().strip() == 'active'

	def enable(self):
		"""
		Enable this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'enable', self.name])

	def disable(self):
		"""
		Disable this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'disable', self.name])

	def start(self):
		"""
		Start this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'start', self.name])

	def stop(self):
		"""
		Stop this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'stop', self.name])

	def restart(self):
		"""
		Restart this service in systemd
		:return:
		"""
		subprocess.run(['systemctl', 'restart', self.name])



class Table:
	"""
	Displays a table of data
	"""
	def __init__(self, columns: list):
		"""
		Initialize the table with the columns to display
		:param columns:
		"""
		self.columns = columns
		self.headers = {
			'num': '#',
			'map': 'Map',
			'session': 'Session',
			'port': 'Port',
			'rcon': 'RCON',
			'enabled': 'Auto-Start',
			'running': 'Service',
			'admin_password': 'Admin Password',
			'players': 'Players',
			'mods': 'Mods',
			'cluster': 'Cluster ID'
		}

	def render(self, services: list):
		"""
		Render the table with the given list of services

		:param services: Services[]
		:return:
		"""
		headers = []
		rows = []
		col_lengths = []

		for col in self.columns:
			if col in self.headers:
				col_lengths.append(len(self.headers[col]))
				headers.append(self.headers[col])
			else:
				col_lengths.append(3)
				headers.append('???')

		row_counter = 0
		for service in services:
			row = []
			row_counter += 1
			counter = 0
			for col in self.columns:
				if col == 'num':
					row.append(str(row_counter))
				elif col == 'map':
					row.append(service.map)
				elif col == 'session':
					row.append(service.session)
				elif col == 'port':
					row.append(service.port)
				elif col == 'rcon':
					row.append(service.rcon if service.rcon_enabled else 'N/A')
				elif col == 'enabled':
					row.append('Enabled' if service.is_enabled() else 'Disabled')
				elif col == 'running':
					row.append('Running' if service.is_running() else 'Stopped')
				elif col == 'admin_password':
					row.append(service.admin_password or '')
				elif col == 'players':
					v = service.rcon_get_number_players()
					row.append(str(v) if v is not None else 'N/A')
				elif col == 'mods':
					row.append(', '.join(service.mods))
				elif col == 'cluster':
					row.append(service.cluster_id or '')
				else:
					row.append('???')

				col_lengths[counter] = max(col_lengths[counter], len(row[-1]))
				counter += 1
			rows.append(row)

		counter = 0
		vals = []
		while counter < len(headers):
			vals.append(headers[counter].ljust(col_lengths[counter]))
			counter += 1
		print('| %s |' % ' | '.join(vals))

		counter = 0
		vals = []
		while counter < len(headers):
			vals.append('-'.ljust(col_lengths[counter], '-'))
			counter += 1
		print('|-%s-|' % '-|-'.join(vals))

		for row in rows:
			counter = 0
			vals = []
			while counter < len(row):
				vals.append(row[counter].ljust(col_lengths[counter]))
				counter += 1
			print('| %s |' % ' | '.join(vals))


def _safe_stop_inner(services, time_message):
	"""

	:param services: Services[]
	:param time_message: str
	:return:
	"""
	players_connected = False
	for s in services:
		if s.is_running():
			players = s.rcon_get_number_players()
			if players is None:
				print('Unable to get player count for %s, RCON is probably not available' % s.session)
				s.stop()
			elif players > 0:
				print('%s has %s players connected, sending warning' % (s.session, players))
				s.rcon_message('Server is shutting down %s' % time_message)
				players_connected = True
			else:
				# RCON enabled, but no players connected.  GREAT!
				print('Saving %s' % s.session)
				s.rcon_save_world()
				sleep(10)
				print('Shutting down %s' % s.session)
				s.stop()
	return players_connected


def safe_stop(services):
	"""
	Safely stop all requested service files
	:param services: Services[]
	:return:
	"""

	maps = []
	for s in services:
		if s.is_running():
			maps.append(s.session)
	if len(maps) > 1:
		discord_alert('maps_stopping', [', '.join(maps)])
	elif len(maps) == 1:
		discord_alert('map_stopping', [maps[0]])

	players_connected = _safe_stop_inner(services, 'in 5 minutes')

	if players_connected:
		print('Waiting a minute until the next warning (5 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, 'in 4 minutes')

	if players_connected:
		print('Waiting a minute until the next warning (4 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, 'in 3 minutes')

	if players_connected:
		print('Waiting a minute until the next warning (3 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, 'in 2 minutes')

	if players_connected:
		print('Waiting a minute until the next warning (2 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, 'in 1 minute')

	if players_connected:
		print('Waiting 30 seconds until the next warning (1 minute remaining)')
		sleep(30)
		players_connected = _safe_stop_inner(services, 'in 30 seconds')

	if players_connected:
		print('Last warning')
		sleep(30)
		_safe_stop_inner(services, 'NOW')

	for s in services:
		if s.is_running():
			players = s.rcon_get_number_players()
			if players is not None:
				# RCON enabled, we can request a manual save
				print('Saving %s' % s.session)
				s.rcon_save_world()
				sleep(10)
			print('Shutting down %s' % s.session)
			s.stop()


def safe_restart(services):
	"""

	:param services: Services[]
	:return:
	"""
	running_services = []
	for s in services:
		if s.is_running():
			running_services.append(s)

	safe_stop(running_services)

	print('Running maps have been stopped, waiting a moment to restart them')
	sleep(5)
	safe_start(running_services, True)


def safe_start(services, ignore_enabled = False):
	"""
	Start all enabled services that are not currently running
	:param services: Services[]
	:param ignore_enabled: bool Set to True to ignore the enabled flag
	:return:
	"""
	for s in services:
		if not s.is_enabled() and not ignore_enabled:
			print('Skipping disabled map %s' % s.session)
		elif s.is_running():
			print('%s already running' % s.session)
		else:
			print('Starting %s, please wait, may take a minute...' % s.session)
			s.start()
			players_connected = None
			last_line = ''
			check_counter = 0
			exec_status = 0
			while check_counter < 120:
				check_counter += 1

				# Print a log of output from the systemd service,
				# provides minimal usefulness, but better than nothing.
				line = subprocess.run([
					'journalctl', '-n', '1', '-u', s.name
				], stdout=subprocess.PIPE).stdout.decode().strip()
				if line != last_line:
					print(line)
					last_line = line
				elif check_counter % 30 == 0 and check_counter < 100:
					print('Waiting about %s seconds...' % ((120 - check_counter) / 2))

				# Watch the exit status of the service,
				# if this changes to something other than 0, it indicates a game crash.
				exec_status = int(subprocess.run([
					'systemctl', 'show', '-p', 'ExecMainStatus', s.name
				], stdout=subprocess.PIPE).stdout.decode().strip()[15:])

				if exec_status == 1:
					print('❗⛔❗ WARNING - Service has exited with status 1')
					print('This may indicate corrupt files, please check logs and verify files with Steam.')
					break
				elif exec_status == 15:
					print('❗⛔❗ WARNING - Service has exited with status 15')
					print('This may indicate that your server ran out of memory.')
					break
				elif exec_status != 0:
					print('❗⛔❗ WARNING - Service has exited with status %s' % exec_status)
					break

				sleep(0.5)

			if exec_status != 0:
				return

			if s.rcon_enabled:
				retry = 0
				print('Waiting for RCON to be available (up to about 2 minutes)...')
				while retry < 20:
					retry += 1
					players_connected = s.rcon_get_number_players()
					if players_connected is None:
						if retry % 5 == 0:
							print('Still waiting...')
						sleep(3)
					else:
						print('RCON Connected!')
						break

			if s.rcon_enabled:
				if players_connected is None:
					print('❗⛔❗ WARNING - Service tried to start, but unable to retrieve any data from RCON.')
					print('Please manually check if the game is available.')
				else:
					discord_alert('map_started', [s.session])
			else:
				discord_alert('map_started', [s.session])


def save_config():
	"""
	Save the management application configuration to disk
	:return:
	"""
	with open(os.path.join(here, '.settings.ini'), 'w') as f:
		config.write(f)
	os.chmod(os.path.join(here, '.settings.ini'), 0o600)


def header(line):
	"""
	Print a header line
	:param line: string
	:return:
	"""
	#os.system('clear')
	# Instead of clearing the screen, just print some newlines.
	# This way errors from the previous screen will be visible.
	print('')
	print('')
	print('')
	print('')
	print('== %s ==' % line)
	print('')


def menu_service(service):
	"""
	Interface for managing an individual service
	:param service:
	:return:
	"""
	while True:
		header('Service Details')
		running = service.is_running()

		print('Map:           %s' % service.map)
		print('Session:       %s' % service.session)
		print('Port:          %s' % service.port)
		print('RCON:          %s' % service.rcon)
		print('Auto-Start:    %s' % ('Yes' if service.is_enabled() else 'No'))

		if service.rcon_enabled:
			# Try to guess the status of the service based on its behaviour
			players = service.rcon_get_number_players()
			if running and players is None:
				print('Status:        Starting')
				print('Players:       N/A')
			else:
				print('Status:        %s' % ('Running' if running else 'Stopped'))
				print('Players:       %s' % players)
		else:
			print('Status:        %s' % ('Running' if running else 'Stopped'))
			print('Players:       %s' % service.rcon_get_number_players())

		print('Mods:          %s' % ', '.join(service.mods))
		print('Cluster ID:    %s' % (service.cluster_id or ''))
		print('Other Options: %s' % service.other_options)
		print('Other Flags:   %s' % service.other_flags)
		print('')

		# Check for common recent issues with the server
		log = subprocess.run([
			'journalctl', '--since', '10 minutes ago', '--no-pager', '-u', service.name
		], stdout=subprocess.PIPE).stdout.decode().strip()
		if 'oom-kill' in log:
			print('❗⛔❗ WARNING - Service was recently killed by the OOM killer')
			print('This may indicate that your server ran out of memory!')
			print('')

		options = []
		if service.is_enabled():
			options.append('[D]isable')
		else:
			options.append('[E]nable')

		options.append('[M]ods | [C]luster | re[N]ame | [F]lags | [O]ptions')

		if service.is_running():
			options.append('s[T]op')
			options.append('[R]estart')
		else:
			options.append('[S]tart')

		options.append('[B]ack')
		opt = input(' | '.join(options) + ': ').lower()

		if opt == 'b':
			return
		elif opt == 'e':
			if not service.is_enabled():
				service.enable()
		elif opt == 'd':
			if service.is_enabled():
				service.disable()
		elif opt == 'm':
			val = input('Enter the mod ID to toggle: ').strip()
			if val != '':
				if val in service.mods:
					service.mods.remove(val)
				else:
					service.mods.append(val)
				service.save()
		elif opt == 'c':
			val = rlinput('Enter new cluster id: ', service.cluster_id).strip()
			service.cluster_id = val
			service.save()
		elif opt == 'n':
			name = service.session
			if '(' in name:
				name = name[:name.index('(')]
			val = rlinput('Please enter new name: ', name).strip()
			if val != '':
				service.rename(val)
		elif opt == 'f':
			val = rlinput('Enter new flags: ', service.other_flags).strip()
			service.other_flags = val
			service.save()
		elif opt == 'o':
			val = rlinput('Enter new options: ', service.other_options).strip()
			service.other_options = val.strip('?')
			service.save()
		elif opt == 's':
			safe_start([service], True)
		elif opt == 't':
			safe_stop([service])
		elif opt == 'r':
			safe_restart([service])
		else:
			print('Invalid option')


def menu_mods():
	"""
	Interface to manage mods across all maps
	:return:
	"""
	while True:
		header('Mods Configuration')
		table = Table(['session', 'mods'])
		table.render(services)
		print('')
		opt = input('[E]nable mod on all maps | [D]isable mod on all maps | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'e':
			val = input('Enter the mod ID to enable: ').strip()
			if val != '':
				for s in services:
					if val not in s.mods:
						s.mods.append(val)
						s.save()
		elif opt == 'd':
			val = input('Enter the mod ID to disable: ').strip()
			if val != '':
				for s in services:
					if val in s.mods:
						s.mods.remove(val)
						s.save()
		else:
			print('Invalid option')


def menu_cluster():
	while True:
		header('Cluster Configuration')
		table = Table(['session', 'cluster'])
		table.render(services)
		print('')
		opt = input('[C]hange cluster id on all maps | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'c':
			print('WARNING - changing the cluster ID may result in loss of data!')
			vals = []
			for s in services:
				if s.cluster_id and s.cluster_id not in vals:
					vals.append(s.cluster_id)
			if len(vals) == 1:
				val = rlinput('Enter new cluster id: ', vals[0]).strip()
			else:
				val = input('Enter new cluster id: ').strip()
			for s in services:
				s.cluster_id = val
				s.save()
		else:
			print('Invalid option')


def menu_admin_password():
	"""
	Interface to manage rcon and administration password
	:return:
	"""
	while True:
		header('Admin and RCON Configuration')
		table = Table(['session', 'admin_password', 'rcon'])
		table.render(services)
		print('')
		opt = input('[C]hange admin password on all | [E]nable RCON on all | [D]isable RCON on all | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'e':
			for s in services:
				s.rcon_enabled = True
				s.save()
		elif opt == 'd':
			print('WARNING - disabling RCON will prevent clean shutdowns!')
			for s in services:
				s.rcon_enabled = False
				s.save()
		elif opt == 'c':
			val = input('Enter new password: ').strip()
			if val:
				for s in services:
					s.admin_password = val.replace('"', '').replace(' ', '')
					s.save()
		else:
			print('Invalid option')


def menu_discord():
	while True:
		header('Discord Integration')
		enabled = config['Discord'].get('enabled', '0') == '1'
		webhook = config['Discord'].get('webhook', '')
		if webhook == '':
			print('Discord has not been integrated yet.')
			print('')
			print('If you would like to send shutdown / startup notifications to Discord, you can')
			print('do so by adding a Webhook (Discord -> Settings -> Integrations -> Webhooks -> Create Webhook)')
			print('and pasting the generated URL here.')
			print('')
			print('URL or just the character "b" to go [B]ack.')
			opt = input(': ')

			if 'https://' in opt:
				config['Discord']['webhook'] = opt
				config['Discord']['enabled'] = '1'
				save_config()
			else:
				return
		else:
			discord_channel = None
			discord_guild = None
			discord_name = None
			req = request.Request(webhook, headers={'Accept': 'application/json', 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0'}, method='GET')
			try:
				with request.urlopen(req) as resp:
					data = json.loads(resp.read().decode('utf-8'))
					discord_channel = data['channel_id']
					discord_guild = data['guild_id']
					discord_name = data['name']
			except urlerror.HTTPError as e:
				print('Error: %s' % e)
			except json.JSONDecodeError as e:
				print('Error: %s' % e)

			if enabled and discord_name:
				print('Discord integration is currently available and enabled!')
			elif discord_name:
				print('Discord integration is currently DISABLED.')
			else:
				print('Discord integration is currently unavailable, bad Webhook URL?')
			print('')
			print('Discord Webhook URL:  %s' % webhook[0:webhook.rindex('/')+5] + '************' + webhook[-4:])
			print('Discord Channel ID:   %s' % discord_channel)
			print('Discord Guild ID:     %s' % discord_guild)
			print('Discord Webhook Name: %s' % discord_name)
			print('')

			options = []
			if enabled:
				options.append('[D]isable')
			else:
				options.append('[E]nable')

			options.append('[C]hange Discord webhook URL')
			options.append('configure [M]essages')
			options.append('[B]ack')
			print(' | '.join(options))
			opt = input(': ').lower()

			if opt == 'b':
				return
			elif opt == 'm':
				menu_discord_messages()
			elif opt == 'c':
				print('do so by adding a Webhook (Discord -> Settings -> Integrations -> Webhooks -> Create Webhook)')
				print('and pasting the generated URL here.')
				val = input('Enter new Discord webhook URL: ').strip()
				if val != '':
					config['Discord']['webhook'] = val
					save_config()
			elif opt == 'e':
				config['Discord']['enabled'] = '1'
				save_config()
			elif opt == 'd':
				config['Discord']['enabled'] = '0'
				save_config()
			else:
				print('Invalid option')


def menu_discord_messages():
	while True:
		header('Discord Messages')
		print('The following messages will be sent to Discord when certain events occur.')
		print('')
		print('| 1 | Map Started   | ' + discord_message('map_started'))
		print('| 2 | Maps Stopping | ' + discord_message('map_stopping'))
		print('| 3 | Map Stopping  | ' + discord_message('maps_stopping'))
		print('')
		opt = input('[1-3] change message | [B]ack: ').lower()
		key = None
		val = ''

		if opt == 'b':
			return
		elif opt == '1':
			key = 'map_started'
			print('')
			print('Edit the message, left/right works to move cursor.  Blank to use default.')
			val = rlinput('Map Started: ', discord_message(key)).strip()
		elif opt == '2':
			key = 'map_stopping'
			print('')
			print('Edit the message, left/right works to move cursor.  Blank to use default.')
			val = rlinput('Maps Stopping: ', discord_message(key)).strip()
		elif opt == '3':
			key = 'maps_stopping'
			print('')
			print('Edit the message, left/right works to move cursor.  Blank to use default.')
			val = rlinput('Map Stopping: ', discord_message(key)).strip()
		else:
			print('Invalid option')

		if key is not None:
			config['Discord'][key] = val.replace('%', '%%')
			save_config()


def menu_main():
	stay = True
	while stay:
		header('Welcome to the ARK Survival Ascended Linux Server Manager')
		print('Find an issue? https://github.com/cdp1337/ARKSurvivalAscended-Linux/issues')
		print('Want to help support this project? https://ko-fi.com/Q5Q013RM9Q')
		print('')
		table = Table(['num', 'map', 'session', 'port', 'rcon', 'enabled', 'running', 'players'])
		table.render(services)

		print('')
		print('1-%s to manage individual map settings' % len(services))
		print('Configure: [M]ods | [C]luster | [A]dmin password/RCON | re[N]ame | [D]iscord integration')
		print('Control: [S]tart all | s[T]op all | [R]estart all | [U]pdate')
		print('or [Q]uit to exit')
		opt = input(': ').lower()

		if opt == 'q':
			stay = False
		elif opt == 'm':
			menu_mods()
		elif opt == 'c':
			menu_cluster()
		elif opt == 'a':
			menu_admin_password()
		elif opt == 'd':
			menu_discord()
		elif opt == 'n':
			val = input('Please enter new name: ').strip()
			if val != '':
				for s in services:
					s.rename(val)
		elif opt == 's':
			safe_start(services)
		elif opt == 't':
			safe_stop(services)
		elif opt == 'r':
			safe_restart(services)
		elif opt == 'u':
			running = False
			for s in services:
				if s.is_running():
					running = True
					break
			if running:
				print('ERROR - cannot update game from Steam while a map is running!')
			else:
				subprocess.run([os.path.join(here, 'update.sh')], stderr=sys.stderr, stdout=sys.stdout)
		elif opt.isdigit() and 1 <= int(opt) <= len(services):
			menu_service(services[int(opt)-1])

# Get the script configuration, useful for settings not directly related to the game
config = configparser.ConfigParser()
config.read(os.path.join(here, '.settings.ini'))
if 'Discord' not in config.sections():
	config['Discord'] = {}

services = []
services_path = os.path.join(here, 'services')
for f in os.listdir(services_path):
	if f.endswith('.conf'):
		services.append(Services(os.path.join(services_path, f)))

menu_main()
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/manage.py
chmod +x $GAME_DIR/manage.py

cat > $GAME_DIR/backup.sh <<EOF
#!/bin/bash
#
# Backup all player data
#
# DYNAMICALLY GENERATED FILE! Edit at your own risk

GAME_MAPS="$GAME_MAPS"
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
SAVE_DIR="$GAME_DIR/AppFiles/ShooterGame/Saved"

# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-active \$MAP)" == "active" ]; then
		echo "WARNING - \$MAP is still running"
		RUNNING=1
	fi
done

if [ \$RUNNING -eq 1 ]; then
	echo "At least one map is still running, do you still want to backup? (y/N): "
	read UP
	if [ "\$UP" != "y" -a "\$UP" != "Y" ]; then
		exit 1
	fi
fi

# Prep the various directories
[ -e \$SAVE_DIR/.services ] || mkdir \$SAVE_DIR/.services
[ -e \$GAME_DIR/backups ] || mkdir \$GAME_DIR/backups

# Copy service files from systemd
cp /etc/systemd/system/ark-*.service.d \$SAVE_DIR/.services -r

FILES="clusters Config/WindowsServer .services SavedArks"
TGZ="\$GAME_DIR/backups/ArkSurvivalAscended-\$(date +%Y-%m-%d_%H-%M).tgz"

tar -czf \$TGZ \
	-C \$SAVE_DIR  \
	--exclude='*_WP_0*.ark' \
	--exclude='*_WP_1*.ark' \
	--exclude='*.profilebak' \
	--exclude='*.tribebak' \
	\$FILES

if [ \$? -eq 0 ]; then
	echo "Created backup \$TGZ"
fi

# Cleanup
rm -fr "\$SAVE_DIR/.services"
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/backup.sh
chmod +x $GAME_DIR/backup.sh

cat > $GAME_DIR/restore.sh <<EOF
#!/bin/bash
#
# Restore all player data from a backup file
#
# DYNAMICALLY GENERATED FILE! Edit at your own risk

GAME_MAPS="$GAME_MAPS"
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
SAVE_DIR="$GAME_DIR/AppFiles/ShooterGame/Saved"

if [ \$(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi

# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in \$GAME_MAPS; do
	if [ "\$(systemctl is-active \$MAP)" == "active" ]; then
		echo "WARNING - \$MAP is still running"
		echo "Restore cannot proceed with a map actively running."
		exit 1
	fi
done

if [ -z "\$1" ]; then
	echo "ERROR - no source file specified"
	echo "Usage: \$0 <source.tgz>"
	exit 1
fi

if [ ! -e "\$1" ]; then
	echo "ERROR - cannot read source \$1"
	echo "Usage: \$0 <source.tgz>"
	exit 1
fi

echo "Extracting \$1"
tar -xzf "\$1" -C \$SAVE_DIR
if [ \$? -ne 0 ]; then
	echo "ERROR - failed to extract \$1"
	exit 1
fi

if [ -e \$SAVE_DIR/.services ]; then
	echo "Restoring service files"
	chown -R root:root \$SAVE_DIR/.services
	cp \$SAVE_DIR/.services/* /etc/systemd/system/ -r
	systemctl daemon-reload
	rm -fr "\$SAVE_DIR/.services"
fi

echo "Ensuring permissions"
chown -R \$GAME_USER:\$GAME_USER \$SAVE_DIR
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

# Ensure cluster resources exist
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/PlayersJoinNoCheckList.txt"
sudo -u $GAME_USER touch "$GAME_DIR/AppFiles/ShooterGame/Saved/clusters/admins.txt"

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
echo 'Wanna stop by and chat? https://discord.gg/48hHdm5EgA'
echo 'Have an issue or feature request? https://github.com/cdp1337/ARKSurvivalAscended-Linux/issues'
echo 'Help support this and other projects? https://ko-fi.com/Q5Q013RM9Q'
echo ''
echo ''
echo '! IMPORTANT !'
echo 'to manage the server, as root/sudo run the following utility'
echo "$GAME_DIR/manage.py"
