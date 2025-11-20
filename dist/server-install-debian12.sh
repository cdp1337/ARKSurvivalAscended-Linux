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
# @WARLOCK-IMAGE https://files.eval.bz/warlock/ark_460x215.jpg
# @WARLOCK-ICON https://files.eval.bz/warlock/ark-128x128.png
# @WARLOCK-THUMBNAIL https://files.eval.bz/warlock/ark_460x215.jpg
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
#   --reset-proton - Reset proton directories back to default
#   --force-reinstall - Force a reinstall of the game binaries, mods, and engine
#   --uninstall - Uninstall the game server
#   --install-custom-map - Install a custom map (in addition to the defaults)
#   --dir=<path> - Use a custom installation directory instead of the default
#   --non-interactive - Run the installer in non-interactive mode (useful for scripted installs)
#   --skip-firewall - Skip installing/configuring the firewall
#
# Changelog:
#   202511XX - Support custom installation directory
#            - Add support for some custom usecases of the installer
#            - Bump Proton to 10.25
#            - Fix for more flexible support for game options
#            - Backport 74.24 Steam fix into legacy start/stop scripts
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

INSTALLER_VERSION="v20251105~DEV"
# https://github.com/GloriousEggroll/proton-ge-custom
PROTON_VERSION="10-25"
GAME="ArkSurvivalAscended"
GAME_USER="steam"
GAME_DIR="/home/$GAME_USER/$GAME"
REPO="cdp1337/ARKSurvivalAscended-Linux"
DISCORD="https://discord.gg/jyFsweECPb"
FUNDING="https://ko-fi.com/bitsandbytes"
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

function usage() {
  cat >&2 <<EOD
Usage: $0 [options]

Options:
    --reset-proton - Reset proton directories back to default
    --force-reinstall - Force a reinstall of the game binaries, mods, and engine
    --uninstall - Uninstall the game server
    --install-custom-map - Install a custom map (in addition to the defaults)
    --dir=<path> - Use a custom installation directory instead of the default
    --non-interactive - Run the installer in non-interactive mode (useful for scripted installs)
    --skip-firewall - Skip installing/configuring the firewall

Installs ARK Survival Ascended Dedicated Server on Debian/Ubuntu systems

Uses Glorious Eggroll's build of Proton
Please ensure to run this script as root (or at least with sudo)

@LICENSE AGPLv3
EOD
  exit 1
}

# Parse arguments
OPT_RESET_PROTON=0
OPT_FORCE_REINSTALL=0
OPT_UNINSTALL=0
OPT_INSTALL_CUSTOM_MAP=0
OPT_OVERRIDE_DIR=""
OPT_NONINTERACTIVE=0
OPT_SKIP_FIREWALL=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--reset-proton) OPT_RESET_PROTON=1; shift 1;;
		--force-reinstall) OPT_FORCE_REINSTALL=1; shift 1;;
		--uninstall) OPT_UNINSTALL=1; shift 1;;
		--install-custom-map) OPT_INSTALL_CUSTOM_MAP=1; shift 1;;
		--dir=*) OPT_OVERRIDE_DIR="${1#*=}"; shift 1;;
		--non-interactive) OPT_NONINTERACTIVE=1; shift 1;;
		--skip-firewall) OPT_SKIP_FIREWALL=1; shift 1;;
		-h|--help) usage;;
	esac
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi
##
# Simple download utility function
#
# Uses either cURL or wget based on which is available
#
# Returns 0 on success, 1 on failure
function download() {
	local SOURCE="$1"
	local DESTINATION="$2"

	if [ -z "$SOURCE" ] || [ -z "$DESTINATION" ]; then
		echo "download: Missing required parameters!" >&2
		return 1
	fi

	if [ -n "$(which curl)" ]; then
		if curl -sL "$SOURCE" -o "$DESTINATION"; then
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif [ -n "$(which wget)" ]; then
		if wget -q "$SOURCE" -O "$DESTINATION"; then
			return 0
		else
			echo "download: wget failed to download $SOURCE" >&2
			return 1
		fi
	else
		echo "download: Neither curl nor wget is installed, cannot download!" >&2
		return 1
	fi
}

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
		if ! download "$PROTON_URL" "/opt/script-collection/$PROTON_TGZ"; then
			echo "install_proton: Cannot download Proton from ${PROTON_URL}!" >&2
			return 1
		fi
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
# Get the operating system version
#
# Just the major version number is returned
#
function os_version() {
	if [ "$(uname -s)" == 'FreeBSD' ]; then
		local _V="$(uname -K)"
		if [ ${#_V} -eq 6 ]; then
			echo "${_V:0:1}"
		elif [ ${#_V} -eq 7 ]; then
			echo "${_V:0:2}"
		fi

	elif [ -f '/etc/os-release' ]; then
		local VERS="$(egrep '^VERSION_ID=' /etc/os-release | sed 's:VERSION_ID=::')"

		if [[ "$VERS" =~ '"' ]]; then
			# Strip quotes around the OS name
			VERS="$(echo "$VERS" | sed 's:"::g')"
		fi

		if [[ "$VERS" =~ \. ]]; then
			# Remove the decimal point and everything after
			# Trims "24.04" down to "24"
			VERS="${VERS/\.*/}"
		fi

		if [[ "$VERS" =~ "v" ]]; then
			# Remove the "v" from the version
			# Trims "v24" down to "24"
			VERS="${VERS/v/}"
		fi

		echo "$VERS"

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
	OS_VERSION="$(os_version)"

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

		if [ "$OS_VERSION" -le 12 ]; then
			apt install -y software-properties-common apt-transport-https dirmngr ca-certificates lib32gcc-s1

			# Enable "non-free" repos for Debian (for steamcmd)
			# https://stackoverflow.com/questions/76688863/apt-add-repository-doesnt-work-on-debian-12
			add-apt-repository -y -U http://deb.debian.org/debian -c non-free-firmware -c non-free
			if [ $? -ne 0 ]; then
				echo "Workaround failed to add non-free repos, trying new method instead"
				apt-add-repository -y non-free
			fi
		else
			# Debian Trixie and later
			if [ -e /etc/apt/sources.list ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list
				fi
			elif [ -e /etc/apt/sources.list.d/debian.sources ]; then
				if ! grep -q ' non-free ' /etc/apt/sources.list.d/debian.sources; then
					sed -i 's/main/main non-free-firmware non-free contrib/g' /etc/apt/sources.list.d/debian.sources
				fi
			else
				echo "Could not find a sources.list file to enable non-free repos" >&2
				exit 1
			fi
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
	local TTY_IP="$(who am i | awk '{print $NF}' | sed 's/[()]//g')"
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

# ==============================================================================
# Bash INI Parser Library
# ==============================================================================
# A lightweight library for manipulating INI configuration files in Bash scripts
#
# Author: Leandro Ferreira (https://leandrosf.com)
# Version: 0.0.1
# License: BSD
# GitHub: https://github.com/lsferreira42
# ==============================================================================

# Configuration
# These variables can be overridden by setting environment variables with the same name
# For example: export INI_DEBUG=1 before sourcing this library
INI_DEBUG=${INI_DEBUG:-0} # Set to 1 to enable debug messages
INI_STRICT=${INI_STRICT:-0} # Set to 1 for strict validation of section/key names
INI_ALLOW_EMPTY_VALUES=${INI_ALLOW_EMPTY_VALUES:-1} # Set to 1 to allow empty values
INI_ALLOW_SPACES_IN_NAMES=${INI_ALLOW_SPACES_IN_NAMES:-1} # Set to 1 to allow spaces in section/key names

# ==============================================================================
# Utility Functions
# ==============================================================================

# Print debug messages
function ini_debug() {
    if [ "${INI_DEBUG}" -eq 1 ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Print error messages
function ini_error() {
    echo "[ERROR] $1" >&2
}

# Validate section name
function ini_validate_section_name() {
    local section="$1"

    if [ -z "$section" ]; then
        ini_error "Section name cannot be empty"
        return 1
    fi

    if [ "${INI_STRICT}" -eq 1 ]; then
        # Check for illegal characters in section name
        if [[ "$section" =~ [\[\]\=] ]]; then
            ini_error "Section name contains illegal characters: $section"
            return 1
        fi
    fi

    if [ "${INI_ALLOW_SPACES_IN_NAMES}" -eq 0 ] && [[ "$section" =~ [[:space:]] ]]; then
        ini_error "Section name contains spaces: $section"
        return 1
    fi

    return 0
}

# Validate key name
function ini_validate_key_name() {
    local key="$1"

    if [ -z "$key" ]; then
        ini_error "Key name cannot be empty"
        return 1
    fi

    if [ "${INI_STRICT}" -eq 1 ]; then
        # Check for illegal characters in key name
        if [[ "$key" =~ [\[\]\=] ]]; then
            ini_error "Key name contains illegal characters: $key"
            return 1
        fi
    fi

    if [ "${INI_ALLOW_SPACES_IN_NAMES}" -eq 0 ] && [[ "$key" =~ [[:space:]] ]]; then
        ini_error "Key name contains spaces: $key"
        return 1
    fi

    return 0
}

# Create a secure temporary file
function ini_create_temp_file() {
    mktemp "${TMPDIR:-/tmp}/ini_XXXXXXXXXX"
}

# Trim whitespace from start and end of a string
function ini_trim() {
    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Escape special characters in a string for regex matching
function ini_escape_for_regex() {
    echo "$1" | sed -e 's/[]\/()$*.^|[]/\\&/g'
}

# ==============================================================================
# File Operations
# ==============================================================================

function ini_check_file() {
    local file="$1"

    # Check if file parameter is provided
    if [ -z "$file" ]; then
        ini_error "File path is required"
        return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_debug "File does not exist, attempting to create: $file"
        # Create directory if it doesn't exist
        local dir
        dir=$(dirname "$file")
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" 2>/dev/null || {
                ini_error "Could not create directory: $dir"
                return 1
            }
        fi

        # Create the file
        if ! touch "$file" 2>/dev/null; then
            ini_error "Could not create file: $file"
            return 1
        fi
        ini_debug "File created successfully: $file"
    fi

    # Check if file is writable
    if [ ! -w "$file" ]; then
        ini_error "File is not writable: $file"
        return 1
    fi

    return 0
}

# ==============================================================================
# Core Functions
# ==============================================================================

function ini_read() {
    local file="$1"
    local section="$2"
    local key="$3"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ] || [ -z "$key" ]; then
        ini_error "ini_read: Missing required parameters"
        return 1
    fi

    # Validate section and key names only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
        ini_validate_key_name "$key" || return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_error "File not found: $file"
        return 1
    fi

    # Escape section and key for regex pattern
    local escaped_section
    escaped_section=$(ini_escape_for_regex "$section")
    local escaped_key
    escaped_key=$(ini_escape_for_regex "$key")

    local section_pattern="^\[$escaped_section\]"
    local in_section=0

    ini_debug "Reading key '$key' from section '$section' in file: $file"

    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*[#\;] ]]; then
            continue
        fi

        # Check for section
        if [[ "$line" =~ $section_pattern ]]; then
            in_section=1
            ini_debug "Found section: $section"
            continue
        fi

        # Check if we've moved to a different section
        if [[ $in_section -eq 1 && "$line" =~ ^\[[^]]+\] ]]; then
            ini_debug "Reached end of section without finding key"
            return 1
        fi

        # Check for key in the current section
        if [[ $in_section -eq 1 ]]; then
            local key_pattern="^[[:space:]]*${escaped_key}[[:space:]]*="
            if [[ "$line" =~ $key_pattern ]]; then
                local value="${line#*=}"
                # Trim whitespace
                value=$(ini_trim "$value")

                # Check for quoted values
                if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                    # Remove the quotes
                    value="${BASH_REMATCH[1]}"
                    # Handle escaped quotes within the value
                    value="${value//\\\"/\"}"
                fi

                ini_debug "Found value: $value"
                echo "$value"
                return 0
            fi
        fi
    done < "$file"

    ini_debug "Key not found: $key in section: $section"
    return 1
}

function ini_list_sections() {
    local file="$1"

    # Validate parameters
    if [ -z "$file" ]; then
        ini_error "ini_list_sections: Missing file parameter"
        return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_error "File not found: $file"
        return 1
    fi

    ini_debug "Listing sections in file: $file"

    # Extract section names
    grep -o '^\[[^]]*\]' "$file" 2>/dev/null | sed 's/^\[\(.*\)\]$/\1/'
    return 0
}

function ini_list_keys() {
    local file="$1"
    local section="$2"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ]; then
        ini_error "ini_list_keys: Missing required parameters"
        return 1
    fi

    # Validate section name only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_error "File not found: $file"
        return 1
    fi

    # Escape section for regex pattern
    local escaped_section
    escaped_section=$(ini_escape_for_regex "$section")
    local section_pattern="^\[$escaped_section\]"
    local in_section=0

    ini_debug "Listing keys in section '$section' in file: $file"

    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*[#\;] ]]; then
            continue
        fi

        # Check for section
        if [[ "$line" =~ $section_pattern ]]; then
            in_section=1
            ini_debug "Found section: $section"
            continue
        fi

        # Check if we've moved to a different section
        if [[ $in_section -eq 1 && "$line" =~ ^\[[^]]+\] ]]; then
            break
        fi

        # Extract key name from current section
        if [[ $in_section -eq 1 && "$line" =~ ^[[:space:]]*[^=]+= ]]; then
            local key="${line%%=*}"
            key=$(ini_trim "$key")
            ini_debug "Found key: $key"
            echo "$key"
        fi
    done < "$file"

    return 0
}

function ini_section_exists() {
    local file="$1"
    local section="$2"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ]; then
        ini_error "ini_section_exists: Missing required parameters"
        return 1
    fi

    # Validate section name only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_debug "File not found: $file"
        return 1
    fi

    # Escape section for regex pattern
    local escaped_section
    escaped_section=$(ini_escape_for_regex "$section")

    ini_debug "Checking if section '$section' exists in file: $file"

    # Check if section exists
    grep -q "^\[$escaped_section\]" "$file"
    local result=$?

    if [ $result -eq 0 ]; then
        ini_debug "Section found: $section"
    else
        ini_debug "Section not found: $section"
    fi

    return $result
}

function ini_add_section() {
    local file="$1"
    local section="$2"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ]; then
        ini_error "ini_add_section: Missing required parameters"
        return 1
    fi

    # Validate section name only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
    fi

    # Check and create file if needed
    ini_check_file "$file" || return 1

    # Check if section already exists
    if ini_section_exists "$file" "$section"; then
        ini_debug "Section already exists: $section"
        return 0
    fi

    ini_debug "Adding section '$section' to file: $file"

    # Add a newline if file is not empty
    if [ -s "$file" ]; then
        echo "" >> "$file"
    fi

    # Add the section
    echo "[$section]" >> "$file"

    return 0
}

function ini_write() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ] || [ -z "$key" ]; then
        ini_error "ini_write: Missing required parameters"
        return 1
    fi

    # Validate section and key names only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
        ini_validate_key_name "$key" || return 1
    fi

    # Check for empty value if not allowed
    if [ -z "$value" ] && [ "${INI_ALLOW_EMPTY_VALUES}" -eq 0 ]; then
        ini_error "Empty values are not allowed"
        return 1
    fi

    # Check and create file if needed
    ini_check_file "$file" || return 1

    # Create section if it doesn't exist
    ini_add_section "$file" "$section" || return 1

    # Escape section and key for regex pattern
    local escaped_section
    escaped_section=$(ini_escape_for_regex "$section")
    local escaped_key
    escaped_key=$(ini_escape_for_regex "$key")

    local section_pattern="^\[$escaped_section\]"
    local key_pattern="^[[:space:]]*${escaped_key}[[:space:]]*="
    local in_section=0
    local found_key=0
    local temp_file
    temp_file=$(ini_create_temp_file)

    ini_debug "Writing key '$key' with value '$value' to section '$section' in file: $file"

    # Special handling for values with quotes or special characters
    if [ "${INI_STRICT}" -eq 1 ] && [[ "$value" =~ [[:space:]\"\'\`\&\|\<\>\;\$] ]]; then
        value="\"${value//\"/\\\"}\""
        ini_debug "Value contains special characters, quoting: $value"
    fi

    # Process the file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Check for section
        if [[ "$line" =~ $section_pattern ]]; then
            in_section=1
            echo "$line" >> "$temp_file"
            continue
        fi

        # Check if we've moved to a different section
        if [[ $in_section -eq 1 && "$line" =~ ^\[[^]]+\] ]]; then
            # Add the key-value pair if we haven't found it yet
            if [ $found_key -eq 0 ]; then
                echo "$key=$value" >> "$temp_file"
                found_key=1
            fi
            in_section=0
        fi

        # Update the key if it exists in the current section
        if [[ $in_section -eq 1 && "$line" =~ $key_pattern ]]; then
            echo "$key=$value" >> "$temp_file"
            found_key=1
            continue
        fi

        # Write the line to the temp file
        echo "$line" >> "$temp_file"
    done < "$file"

    # Add the key-value pair if we're still in the section and haven't found it
    if [ $in_section -eq 1 ] && [ $found_key -eq 0 ]; then
        echo "$key=$value" >> "$temp_file"
    fi

    # Use atomic operation to replace the original file
    mv "$temp_file" "$file"

    ini_debug "Successfully wrote key '$key' with value '$value' to section '$section'"
    return 0
}

function ini_remove_section() {
    local file="$1"
    local section="$2"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ]; then
        ini_error "ini_remove_section: Missing required parameters"
        return 1
    fi

    # Validate section name only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_error "File not found: $file"
        return 1
    fi

    # Escape section for regex pattern
    local escaped_section
    escaped_section=$(ini_escape_for_regex "$section")
    local section_pattern="^\[$escaped_section\]"
    local in_section=0
    local temp_file
    temp_file=$(ini_create_temp_file)

    ini_debug "Removing section '$section' from file: $file"

    # Process the file line by line
    while IFS= read -r line; do
        # Check for section
        if [[ "$line" =~ $section_pattern ]]; then
            in_section=1
            continue
        fi

        # Check if we've moved to a different section
        if [[ $in_section -eq 1 && "$line" =~ ^\[[^]]+\] ]]; then
            in_section=0
        fi

        # Write the line to the temp file if not in the section to be removed
        if [ $in_section -eq 0 ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$file"

    # Use atomic operation to replace the original file
    mv "$temp_file" "$file"

    ini_debug "Successfully removed section '$section'"
    return 0
}

function ini_remove_key() {
    local file="$1"
    local section="$2"
    local key="$3"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ] || [ -z "$key" ]; then
        ini_error "ini_remove_key: Missing required parameters"
        return 1
    fi

    # Validate section and key names only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
        ini_validate_key_name "$key" || return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_error "File not found: $file"
        return 1
    fi

    # Escape section and key for regex pattern
    local escaped_section
    escaped_section=$(ini_escape_for_regex "$section")
    local escaped_key
    escaped_key=$(ini_escape_for_regex "$key")

    local section_pattern="^\[$escaped_section\]"
    local key_pattern="^[[:space:]]*${escaped_key}[[:space:]]*="
    local in_section=0
    local temp_file
    temp_file=$(ini_create_temp_file)

    ini_debug "Removing key '$key' from section '$section' in file: $file"

    # Process the file line by line
    while IFS= read -r line; do
        # Check for section
        if [[ "$line" =~ $section_pattern ]]; then
            in_section=1
            echo "$line" >> "$temp_file"
            continue
        fi

        # Check if we've moved to a different section
        if [[ $in_section -eq 1 && "$line" =~ ^\[[^]]+\] ]]; then
            in_section=0
        fi

        # Skip the key to be removed
        if [[ $in_section -eq 1 && "$line" =~ $key_pattern ]]; then
            continue
        fi

        # Write the line to the temp file
        echo "$line" >> "$temp_file"
    done < "$file"

    # Use atomic operation to replace the original file
    mv "$temp_file" "$file"

    ini_debug "Successfully removed key '$key' from section '$section'"
    return 0
}

# ==============================================================================
# Extended Functions
# ==============================================================================

function ini_get_or_default() {
    local file="$1"
    local section="$2"
    local key="$3"
    local default_value="$4"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ] || [ -z "$key" ]; then
        ini_error "ini_get_or_default: Missing required parameters"
        return 1
    fi

    # Try to read the value
    local value
    value=$(ini_read "$file" "$section" "$key" 2>/dev/null)
    local result=$?

    # Return the value or default
    if [ $result -eq 0 ]; then
        echo "$value"
    else
        echo "$default_value"
    fi

    return 0
}

function ini_import() {
    local source_file="$1"
    local target_file="$2"
    local import_sections=("${@:3}")

    # Validate parameters
    if [ -z "$source_file" ] || [ -z "$target_file" ]; then
        ini_error "ini_import: Missing required parameters"
        return 1
    fi

    # Check if source file exists
    if [ ! -f "$source_file" ]; then
        ini_error "Source file not found: $source_file"
        return 1
    fi

    # Check and create target file if needed
    ini_check_file "$target_file" || return 1

    ini_debug "Importing from '$source_file' to '$target_file'"

    # Get sections from source file
    local sections
    sections=$(ini_list_sections "$source_file")

    # Loop through sections
    for section in $sections; do
        # Skip if specific sections are provided and this one is not in the list
        if [ ${#import_sections[@]} -gt 0 ] && ! [[ ${import_sections[*]} =~ $section ]]; then
            ini_debug "Skipping section: $section"
            continue
        fi

        ini_debug "Importing section: $section"

        # Add the section to the target file
        ini_add_section "$target_file" "$section"

        # Get keys in this section
        local keys
        keys=$(ini_list_keys "$source_file" "$section")

        # Loop through keys
        for key in $keys; do
            # Read the value and write it to the target file
            local value
            value=$(ini_read "$source_file" "$section" "$key")
            ini_write "$target_file" "$section" "$key" "$value"
        done
    done

    ini_debug "Import completed successfully"
    return 0
}

function ini_to_env() {
    local file="$1"
    local prefix="$2"
    local section="$3"

    # Validate parameters
    if [ -z "$file" ]; then
        ini_error "ini_to_env: Missing file parameter"
        return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_error "File not found: $file"
        return 1
    fi

    ini_debug "Exporting INI values to environment variables with prefix: $prefix"

    # If section is specified, only export keys from that section
    if [ -n "$section" ]; then
        if [ "${INI_STRICT}" -eq 1 ]; then
            ini_validate_section_name "$section" || return 1
        fi

        local keys
        keys=$(ini_list_keys "$file" "$section")

        for key in $keys; do
            local value
            value=$(ini_read "$file" "$section" "$key")

            # Export the variable with the given prefix
            if [ -n "$prefix" ]; then
                export "${prefix}_${section}_${key}=${value}"
            else
                export "${section}_${key}=${value}"
            fi
        done
    else
        # Export keys from all sections
        local sections
        sections=$(ini_list_sections "$file")

        for section in $sections; do
            local keys
            keys=$(ini_list_keys "$file" "$section")

            for key in $keys; do
                local value
                value=$(ini_read "$file" "$section" "$key")

                # Export the variable with the given prefix
                if [ -n "$prefix" ]; then
                    export "${prefix}_${section}_${key}=${value}"
                else
                    export "${section}_${key}=${value}"
                fi
            done
        done
    fi

    ini_debug "Environment variables set successfully"
    return 0
}

function ini_key_exists() {
    local file="$1"
    local section="$2"
    local key="$3"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ] || [ -z "$key" ]; then
        ini_error "ini_key_exists: Missing required parameters"
        return 1
    fi

    # Validate section and key names only if strict mode is enabled
    if [ "${INI_STRICT}" -eq 1 ]; then
        ini_validate_section_name "$section" || return 1
        ini_validate_key_name "$key" || return 1
    fi

    # Check if file exists
    if [ ! -f "$file" ]; then
        ini_debug "File not found: $file"
        return 1
    fi

    # First check if section exists
    if ! ini_section_exists "$file" "$section"; then
        ini_debug "Section not found: $section"
        return 1
    fi

    # Check if key exists by trying to read it
    if ini_read "$file" "$section" "$key" >/dev/null 2>&1; then
        ini_debug "Key found: $key in section: $section"
        return 0
    else
        ini_debug "Key not found: $key in section: $section"
        return 1
    fi
}

# ==============================================================================
# Array Functions
# ==============================================================================

function ini_read_array() {
    local file="$1"
    local section="$2"
    local key="$3"

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ] || [ -z "$key" ]; then
        ini_error "ini_read_array: Missing required parameters"
        return 1
    fi

    # Read the value
    local value
    value=$(ini_read "$file" "$section" "$key") || return 1

    # Split the array by commas
    # We need to handle quoted values properly
    local -a result=()
    local in_quotes=0
    local current_item=""

    for (( i=0; i<${#value}; i++ )); do
        local char="${value:$i:1}"

        # Handle quotes
        if [ "$char" = '"' ]; then
# shellcheck disable=SC1003
            # Check if the quote is escaped
            if [ $i -gt 0 ] && [ "${value:$((i-1)):1}" = "\\" ]; then
                # It's an escaped quote, keep it
                current_item="${current_item:0:-1}$char"
            else
                # Toggle quote state
                in_quotes=$((1 - in_quotes))
            fi
        # Handle comma separator
        elif [ "$char" = ',' ] && [ $in_quotes -eq 0 ]; then
            # End of an item
            result+=("$(ini_trim "$current_item")")
            current_item=""
        else
            # Add character to current item
            current_item="$current_item$char"
        fi
    done

    # Add the last item
    if [ -n "$current_item" ] || [ ${#result[@]} -gt 0 ]; then
        result+=("$(ini_trim "$current_item")")
    fi

    # Output the array items, one per line
    for item in "${result[@]}"; do
        echo "$item"
    done

    return 0
}

function ini_write_array() {
    local file="$1"
    local section="$2"
    local key="$3"
    shift 3
    local -a array_values=("$@")

    # Validate parameters
    if [ -z "$file" ] || [ -z "$section" ] || [ -z "$key" ]; then
        ini_error "ini_write_array: Missing required parameters"
        return 1
    fi

    # Process array values and handle quoting
    local array_string=""
    local first=1

    for value in "${array_values[@]}"; do
        # Add comma separator if not the first item
        if [ $first -eq 0 ]; then
            array_string="$array_string,"
        else
            first=0
        fi

        # Quote values with spaces or special characters
        if [[ "$value" =~ [[:space:],\"] ]]; then
            # Escape quotes
            value="${value//\"/\\\"}"
            array_string="$array_string\"$value\""
        else
            array_string="$array_string$value"
        fi
    done

    # Write the array string to the ini file
    ini_write "$file" "$section" "$key" "$array_string"
    return $?
}

# Load additional modules if defined
if [ -n "${INI_MODULES_DIR:-}" ] && [ -d "${INI_MODULES_DIR}" ]; then
    for module in "${INI_MODULES_DIR}"/*.sh; do
        if [ -f "$module" ] && [ -r "$module" ]; then
            # shellcheck disable=SC1090,SC1091
            source "$module"
        fi
    done
fi


##
# Update the installer from Github
#
function ark_update_installer() {
	local REPO="$1"
	local GITHUB_VERSION="$2"
	local TARGET="$3"

	if [ -z "$REPO" ] || [ -z "$GITHUB_VERSION" ] || [ -z "$TARGET" ]; then
		echo "update_installer: Missing required parameters!" >&2
		return 1
	fi

	TMP="$(mktemp)"
	local GITHUB_SOURCE="https://raw.githubusercontent.com/${REPO}/refs/tags/${GITHUB_VERSION}/dist/server-install-debian12.sh"
	if download "$GITHUB_SOURCE" "$TMP"; then
		echo "Downloaded new installer version $GITHUB_VERSION from github.com/${REPO}"
		mv "$TMP" "$TARGET"
		chmod +x "$TARGET"

		return 0
	else
		echo "update_installer: Failed to download installer version ${GITHUB_VERSION} from github.com/${REPO}" >&2
		return 1
	fi
}


############################################
## Pre-exec Checks
############################################

# Allow for auto-update checks
if [ -n "$REPO" -a -n "$(which curl)" -a "${0:0:8}" != "/dev/fd/" ]; then
	# Repo is enabled, curl is available, and the script was NOT dynamically loaded
	# Check if there's an updated version available on Github
	echo "Checking Github for updates..."
	GITHUB_VERSION="$(curl -s -L "https://api.github.com/repos/$REPO/releases?per_page=1&page=1" | grep 'tag_name' | sed 's:.* "\(v[0-9]*\)",:\1:')"
	if [ -n "$GITHUB_VERSION" ]; then
		if [ "$GITHUB_VERSION" != "$INSTALLER_VERSION" ]; then
			echo "A new version of the installer is available!"
			read -p "Do you want to update the installer? (y/N): " -t 10 UPDATE
			case "$UPDATE" in
				[yY]*)
					if ark_update_installer "$REPO" "$GITHUB_VERSION" "$0"; then
						echo "Relaunching installer ${GITHUB_VERSION}"
						exec "$0" "${@}"
						exit 0
					else
						echo "Failed to download updated installer from $GITHUB_SOURCE" >&2
						echo "Resuming with existing installer" >&2
					fi
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

echo "================================================================================"
echo "         	  ARK Survival Ascended *unofficial* Installer $INSTALLER_VERSION"
echo ""

# Determine if this is a new installation or an upgrade (/repair)
if [ -e /etc/systemd/system/ark-island.service ]; then
	INSTALLTYPE="upgrade"
else
	if [ $OPT_NONINTERACTIVE -eq 1 ]; then
		INSTALLTYPE="unattended"
	else
		INSTALLTYPE="new"
	fi
	echo "No existing installation detected, proceeding with new installation"
fi

if [ -n "$OPT_OVERRIDE_DIR" ]; then
	# User requested to change the install dir!
	# This changes the GAME_DIR from the default location to wherever the user requested.
	GAME_DIR="$OPT_OVERRIDE_DIR"
	echo "Using ${GAME_DIR} as the installation directory based on explicit argument"
elif [ "$INSTALLTYPE" == "upgrade" ]; then
	# Check for existing installation directory based on service file
	GAME_DIR="$(egrep '^WorkingDirectory' /etc/systemd/system/ark-island.service | sed 's:.*=\(.*\)/AppFiles/ShooterGame/.*:\1:')"
	echo "Detected installation directory of ${GAME_DIR} based on service registration"
else
	echo "Using default installation directory of ${GAME_DIR}"
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
## Uninstallation
############################################
if [ $OPT_UNINSTALL -eq 1 ]; then
	if [ $OPT_NONINTERACTIVE -eq 1 ]; then
		echo "Non-interactive uninstall selected, proceeding without confirmation"
	else
		echo "WARNING - You have chosen to uninstall ARK Survival Ascended Dedicated Server"
		echo "This process will remove ALL game data, including player data, maps, and binaries."
		echo "This action is IRREVERSIBLE."
		echo ''

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
	fi


	if [ -e "$GAME_DIR/backup.sh" ]; then
		if [ $OPT_NONINTERACTIVE -eq 1 ]; then
			# Non-interactive mode, always backup if possible
			$GAME_DIR/backup.sh
		else
			echo "? Would you like to perform a backup before everything is wiped?"
			echo -n "> (Y/n): "
			read CONFIRM
			if [ "$CONFIRM" != "n" -a "$CONFIRM" != "N" ]; then
				$GAME_DIR/backup.sh
			fi
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

if [ "$INSTALLTYPE" == "new" ]; then
	echo "? Include map names in instance name? e.g. My Awesome ARK Server (Island)"
	echo -n "> (Y/n): "
	read JOINEDSESSIONNAME
	if [ "$JOINEDSESSIONNAME" == "n" -o "$JOINEDSESSIONNAME" == "N" ]; then
		JOINEDSESSIONNAME=0
	else
		JOINEDSESSIONNAME=1
	fi
elif [ -e "$GAME_DIR/.settings.ini" ]; then
	# Detect if it's set in the manager settings file
	JOINEDSESSIONNAME=$(ini_get_or_default "$GAME_DIR/.settings.ini" "Manager" "JoinedSessionName" "True")
	if [ "$JOINEDSESSIONNAME" == "True" ]; then
		JOINEDSESSIONNAME=1
	else
		JOINEDSESSIONNAME=0
	fi
else
	# Existing install but no settings defined, default to legacy behaviour
	JOINEDSESSIONNAME=1
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

if [ $OPT_NONINTERACTIVE -eq 0 ]; then
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
	echo 'Multi-server support is provided via NFS by default,'
	echo 'but other file synchronization are possible if you prefer a custom solution.'
	echo ''
	echo 'This ONLY affects the default NFS, (do not enable if you are using a custom solution like VirtIO-FS or Gluster).'
	if [ "$MULTISERVER" -eq 1 ]; then
		echo "? DISABLE multi-server NFS cluster support? (Maps spread across different servers)"
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
		echo "? Enable multi-server NFS cluster support? (Maps spread across different servers)"
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
fi

if [ "$INSTALLTYPE" == "new" ]; then
	if [ $OPT_SKIP_FIREWALL -eq 1 ]; then
		FIREWALL=0
	elif [ $OPT_NONINTERACTIVE -eq 1 ]; then
		# Non-interactive mode, enable firewall by default
		FIREWALL=1
	else
		echo ''
		echo "? Enable system firewall (UFW by default)?"
		echo -n "> (Y/n): "
		read FIREWALL
		if [ "$FIREWALL" == "n" -o "$FIREWALL" == "N" ]; then
			FIREWALL=0
		else
			FIREWALL=1
		fi
	fi
else
	# Existing installations will either have UFW installed or not.
	# Don't change after the first install.
	FIREWALL=0
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

# Ensure target directory exists and is writable by the target user
# This generally isn't needed when using defaults, but is helpful if the GAME_DIR location is changed.
[ -d "$GAME_DIR" ] || mkdir -p "$GAME_DIR"
chown -R $GAME_USER:$GAME_USER "$GAME_DIR"

# Save the preferences for the manager
if [ "$JOINEDSESSIONNAME" == "1" ]; then
	ini_write "$GAME_DIR/.settings.ini" "Manager" "JoinedSessionName" "True"
else
	ini_write "$GAME_DIR/.settings.ini" "Manager" "JoinedSessionName" "False"
fi

# Preliminary requirements
apt install -y curl sudo python3-venv

if [ "$FIREWALL" == "1" ]; then
	if [ "$(get_enabled_firewall)" == "none" ]; then
		# No firewall installed, go ahead and install UFW
		install_ufw
	fi
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

if [ -n "$REPO" -a "${0:0:8}" == "/dev/fd/" ]; then
	# Script was dynamically loaded, save a copy for future reference
	echo "Saving installer script for future reference..."
	ark_update_installer "$REPO" "$INSTALLER_VERSION" "$GAME_DIR/installer.sh"
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

    # Version 74.24 released on Nov 4th 2025 with the comment "Fixed a crash" introduces a serious bug
	# that causes the game to segfault when attempting to load the Steam API.
	# Being Wildcard, they don't actually provide any reason as to why they're using the Steam API for an Epic game,
	# but it seems to work without the Steam library available.
	#
	# In the logs you will see:
	# Initializing Steam Subsystem for server validation.
	# Steam Subsystem initialized: FAILED
	#
	if [ -e "$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64/steamclient64.dll" ]; then
		echo "Removing broken Steam library to prevent segfault"
		rm -f "$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64/steamclient64.dll"
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

	if [ "$JOINEDSESSIONNAME" == "1" ]; then
		SESSIONNAME="${COMMUNITYNAME} (${DESC})"
	else
		SESSIONNAME="${COMMUNITYNAME}"
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
ExecStart=$PROTON_BIN run ArkAscendedServer.exe ${NAME}?listen?SessionName="${SESSIONNAME}"?RCONPort=${RCONPORT}?ServerAdminPassword=${ADMIN_PASS}?RCONEnabled=True -port=${GAMEPORT} ${GAMEFLAGS} ${MODS_LINE}
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

	# Version 74.24 released on Nov 4th 2025 with the comment "Fixed a crash" introduces a serious bug
	# that causes the game to segfault when attempting to load the Steam API.
	# Being Wildcard, they don't actually provide any reason as to why they're using the Steam API for an Epic game,
	# but it seems to work without the Steam library available.
	#
	# In the logs you will see:
	# Initializing Steam Subsystem for server validation.
	# Steam Subsystem initialized: FAILED
	#
	if [ -e "\$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64/steamclient64.dll" ]; then
		echo "Removing broken Steam library to prevent segfault"
		rm -f "\$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64/steamclient64.dll"
	fi


	if [ \$? -ne 0 ]; then
		echo "Game update failed!" >&2
		exit 1
	fi
}

if \$GAME_DIR/manage.py --is-running; then
	echo "Game server is running, not updating"
	exit 0
fi

update_game
EOF
chown $GAME_USER:$GAME_USER $GAME_DIR/update.sh
chmod +x $GAME_DIR/update.sh
systemctl daemon-reload
systemctl enable ark-updater


# As of v2025.11.02 this script has been ported to the management console.
# If it exists however, replace it with the necessary call to preserve backwards compatibility.
if [ -e "$GAME_DIR/start_all.sh" ]; then
	cat > $GAME_DIR/start_all.sh <<EOF
#!/bin/bash
#
# Start all ARK server maps that are enabled
# DYNAMICALLY GENERATED FILE! Edit at your own risk
GAME_DIR="$GAME_DIR"

\$GAME_DIR/update.sh
\$GAME_DIR/manage.py --start-all
EOF
    chown $GAME_USER:$GAME_USER $GAME_DIR/start_all.sh
    chmod +x $GAME_DIR/start_all.sh
fi


# As of v2025.11.02 this script has been ported to the management console.
# If it exists however, replace it with the necessary call to preserve backwards compatibility.
if [ -e "$GAME_DIR/stop_all.sh" ]; then
	cat > $GAME_DIR/stop_all.sh <<EOF
#!/bin/bash
#
# Stop all ARK server maps that are enabled
# DYNAMICALLY GENERATED FILE! Edit at your own risk
GAME_DIR="$GAME_DIR"

\$GAME_DIR/manage.py --stop-all
EOF
	chown $GAME_USER:$GAME_USER $GAME_DIR/stop_all.sh
	chmod +x $GAME_DIR/stop_all.sh
fi


# Install a management script
sudo -u $GAME_USER python3 -m venv $GAME_DIR/.venv
sudo -u $GAME_USER $GAME_DIR/.venv/bin/pip install rcon
cat > $GAME_DIR/manage.py <<EOF
#!/usr/bin/env python3
import argparse
import os
import shutil
import sys
from time import sleep, time
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
from rcon.exceptions import WrongPassword
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


def str_len(s: str) -> int:
	"""
	Regular len(s) but counts emoji as 2 characters
	:param s:
	:return:
	"""
	length = 0
	for c in s:
		if ord(c) > 0xFFF:
			length += 2
		else:
			length += 1
	return length


def str_ljust(s: str, length: int) -> str:
	"""
	Regular str.ljust() but counts emoji as 2 characters
	:param s:
	:param length:
	:return:
	"""
	characters = len(s)
	width = str_len(s)
	return s.ljust(length - (width - characters))


def discord_alert(message: str, parameters: list):
	enabled = config['Discord'].get('enabled', '0') == '1'
	webhook = config['Discord'].get('webhook', '')
	message = Messages.get(message)

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


class Messages:
	messages = {
		'map_started': {
			'title': 'Map Started (Discord)',
			'default': ':green_square: %s has started'
		},
		'map_stopping': {
			'title': 'Map Stopping (Discord)',
			'default': ':small_red_triangle_down: %s shutting down'
		},
		'maps_stopping': {
			'title': 'Maps Stopping (Discord)',
			'default': ':small_red_triangle_down: Shutting down: %s'
		},
		'shutdown_5min': {
			'title': 'Shutdown Warning 5 Minutes',
			'default': 'Server is shutting down in 5 minutes'
		},
		'shutdown_4min': {
			'title': 'Shutdown Warning 4 Minutes',
			'default': 'Server is shutting down in 4 minutes'
		},
		'shutdown_3min': {
			'title': 'Shutdown Warning 3 Minutes',
			'default': 'Server is shutting down in 3 minutes'
		},
		'shutdown_2min': {
			'title': 'Shutdown Warning 2 Minutes',
			'default': 'Server is shutting down in 2 minutes'
		},
		'shutdown_1min': {
			'title': 'Shutdown Warning 1 Minute',
			'default': 'Server is shutting down in 1 minute'
		},
		'shutdown_30sec': {
			'title': 'Shutdown Warning 30 Seconds',
			'default': 'Server is shutting down in 30 seconds!'
		},
		'shutdown_now': {
			'title': 'Shutdown Warning NOW',
			'default': 'Server is shutting down NOW!'
		},
	}

	@classmethod
	def get(cls, msg: str) -> str:
		"""
		Get the user-defined message or default value if not configured

		:param msg:
		:return:
		"""
		if msg not in cls.messages:
			# Message not defined; just return the input message key
			return msg

		legacy_discords = ('map_started', 'map_stopping', 'maps_stopping')

		configured_message = config['Messages'].get(msg, '')
		if configured_message == '':
			# No configured message, check Discord legacy keys or use default.
			if msg in legacy_discords:
				# The management system prior to 2025.10.31 stored Discord messages in Discord.
				configured_message = config['Discord'].get(msg, '')

		return configured_message if configured_message != '' else cls.messages[msg]['default']


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
					 r'(?P<map>[^/?]*)\?listen\?(?P<args>.*)'
					),
					line
				)

				self.runner = extracted_keys.group('runner')
				self.map = extracted_keys.group('map').strip()
				args = extracted_keys.group('args') + ' '
				self.session = None
				self.port = None
				self.mods = []
				self.cluster_id = None
				self.other_options = ''
				self.other_flags = ''
				self.options = {}

				# Use a tokenizer to parse options and flags
				options_done = False
				quote = None
				param = ''
				for c in args:
					if quote is None and c in ['"', "'"]:
						quote = c
						continue
					if quote is not None and c == quote:
						quote = None
						continue

					if not options_done and quote is None and c in ['?', ' ']:
						# '?' separates options
						if '=' in param:
							opt_key, opt_val = param.split('=', 1)
							if opt_key == 'SessionName':
								self.session = opt_val
							else:
								self.options[opt_key] = opt_val
						else:
							self.options[param] = ''
						param = ''
						if c == ' ':
							options_done = True
						continue

					if options_done and quote is None and c == '-':
						# Tack can be safely ignored
						continue

					if options_done and c == ' ':
						# ' ' separates flags
						if param == '':
							continue

						if '=' in param:
							opt_key, opt_val = param.split('=', 1)
						else:
							opt_key = param
							opt_val = ''

						if opt_key.lower() == 'port':
							self.port = opt_val
						elif opt_key.lower() == 'mods':
							if ',' in opt_val:
								self.mods += opt_val.split(',')
							else:
								self.mods.append(opt_val)
						elif opt_key.lower() == 'clusterid':
							self.cluster_id = opt_val
						else:
							self.other_flags += '-' + param + ' '

						param = ''
						continue

					# Default behaviour; just append the character
					param += c

				self.other_flags = self.other_flags.strip()


	def save(self):
		"""
		Save the service definition back to the service file
		and reload systemd with the new updates.
		:return:
		"""
		options = '?'.join([
			self.map,
			'listen',
			'SessionName="%s"' % self.session
		])

		for key, val in self.options.items():
			if val == '':
				options += '?%s' % key
			elif '?' in val or "'" in val or ' ' in val:
				options += '?%s="%s"' % (key, val)
			else:
				options += '?%s=%s' % (key, val)

		# Strip excessive question marks
		options = options.replace('????', '?')
		options = options.replace('???', '?')
		options = options.replace('??', '?')

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

		if not self.is_rcon_available():
			# RCON is not available due to settings
			return None

		try:
			port = int(self.get_option('RCONPort', only_override=True))
			pswd = self.get_option('ServerAdminPassword')
			with Client('127.0.0.1', port, passwd=pswd, timeout=2) as client:
				return client.run(cmd).strip()
		except:
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

	def get_map_description(self) -> str:
		if self.map == 'BobsMissions_WP':
			return 'Club'
		elif self.map.endswith('_WP'):
			return self.map[:-3]
		else:
			return self.map

	def rename(self, new_name):
		"""
		Rename the session name
		:param new_name:
		:return:
		"""
		new_name = new_name.replace('"', '')
		if config['Manager'].get('JoinedSessionName', 'True') == 'True':
			# Add the map description to the session name if enabled (default option)
			new_name = new_name + ' (' + self.get_map_description() + ')'

		self.session = new_name
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

	def is_rcon_available(self) -> bool:
		"""
		Check if RCON is enabled for this service
		:return:
		"""
		return (
			self.get_option('RCONEnabled') == 'True' and
			self.get_option('RCONPort', only_override=True) != '' and
			self.get_option('ServerAdminPassword') != ''
		)

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

	def get_mod_names(self) -> list:
		"""
		Get the list of mod names for this service
		:return:
		"""
		names = []
		for mod in self.mods:
			mod_name = ModLibrary.resolve_mod_name(mod)
			if mod_name is not None:
				names.append(mod_name + ' (' + mod + ')')
			else:
				names.append('⚠️  NOT INSTALLED (' + mod + ')')
		return names

	def get_pid(self) -> int:
		"""
		Get the PID of the running service, or 0 if not running
		:return:
		"""
		pid = subprocess.run([
			'systemctl', 'show', '-p', 'MainPID', self.name
		], stdout=subprocess.PIPE).stdout.decode().strip()[8:]

		return int(pid)

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""

		# There's no quick way to get the game process PID from systemd,
		# so use ps to find the process based on the map name
		processes = subprocess.run([
			'ps', 'axh', '-o', 'pid,cmd'
		], stdout=subprocess.PIPE).stdout.decode().strip()
		for line in processes.split('\n'):
			pid, cmd = line.strip().split(' ', 1)
			if cmd.startswith('ArkAscendedServer.exe %s?listen' % self.map):
				return int(line.strip().split(' ')[0])
		return 0

	def get_memory_usage(self) -> str:
		"""
		Get the formatted memory usage of the service, or N/A if not running
		:return:
		"""

		pid = self.get_game_pid()

		if pid == 0:
			return 'N/A'

		mem = subprocess.run([
			'ps', 'h', '-p', str(pid), '-o', 'rss'
		], stdout=subprocess.PIPE).stdout.decode().strip()

		if mem.isdigit():
			mem = int(mem)
			if mem >= 1024 * 1024:
				mem_gb = mem / (1024 * 1024)
				return '%.2f GB' % mem_gb
			else:
				mem_mb = mem // 1024
				return '%.0f MB' % mem_mb
		else:
			return 'N/A'

	def get_cpu_usage(self) -> str:
		"""
		Get the formatted CPU usage of the service, or N/A if not running
		:return:
		"""

		pid = self.get_game_pid()

		if pid == 0:
			return 'N/A'

		cpu = subprocess.run([
			'ps', 'h', '-p', str(pid), '-o', '%cpu'
		], stdout=subprocess.PIPE).stdout.decode().strip()

		if cpu.replace('.', '', 1).isdigit():
			return '%.0f%%' % float(cpu)
		else:
			return 'N/A'

	def get_saved_location(self) -> str:
		if self.map == 'BobsMissions_WP':
			map = 'BobsMissions'
		else:
			map = self.map

		return os.path.join(
			here,
			'AppFiles',
			'ShooterGame',
			'Saved',
			'SavedArks',
			map
		)

	def get_num_player_profiles(self) -> int:
		"""
		Get the number of player profiles saved for this service
		:return:
		"""
		profiles_path = self.get_saved_location()
		if os.path.exists(profiles_path):
			return len([
				name for name in os.listdir(profiles_path)
				if name.endswith('.arkprofile')
			])
		return 0

	def get_map_file_size(self) -> int:
		"""
		Get the size of the map data on disk in MB
		:return:
		"""
		map_path = os.path.join(self.get_saved_location(), self.map + '.ark')
		if os.path.exists(map_path):
			return round(os.path.getsize(map_path) // (1024 * 1024))
		else:
			return 0

	def get_option(self, key: str, only_override: bool = False) -> str:
		"""
		Get a specific configuration option for this service,
		from either the service definition or the shared settings.
		:param key: Option key to retrieve
		:param only_override: Set to True to only check the service definition
		:return:
		"""
		if key in self.options:
			return self.options[key]
		elif not only_override and shared_settings is not None:
			return shared_settings['ServerSettings'].get(key, '')
		else:
			return ''

	def get_options(self) -> str:
		"""
		Get all local-defined options as a formatted string
		:return:
		"""
		opts = []
		for key, val in self.options.items():
			# Hide system options
			if key in ('RCONEnabled', 'RCONPort', 'ServerAdminPassword'):
				continue
			if val == '':
				opts.append(key)
			elif '?' in val or "'" in val or ' ' in val:
				opts.append('%s="%s"' % (key, val))
			else:
				opts.append('%s=%s' % (key, val))

		return '?'.join(opts)

	def set_options(self, opts: str):
		"""
		Set all local-defined options from a formatted string
		:param opts:
		:return:
		"""
		# Preserve system options
		options = {}
		for key in ('RCONEnabled', 'RCONPort', 'ServerAdminPassword'):
			val = self.get_option(key, True)
			if val != '':
				options[key] = val

		param = ''
		quote = None
		opts += '?'
		for c in opts:
			if quote is None and c in ['"', "'"]:
				quote = c
				continue

			if quote is not None and c == quote:
				quote = None
				continue

			if quote is None and c == '?':
				if param == '':
					continue

				if '=' in param:
					opt_key, opt_val = param.split('=', 1)
					options[opt_key] = opt_val
				else:
					options[param] = ''

				param = ''
				continue

			param += c

		self.options = options


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
			'running': 'Status',
			'admin_password': 'Admin Password',
			'players': 'Players',
			'mods': 'Mods',
			'cluster': 'Cluster ID',
			'map_size': 'Map Size (MB)',
			'player_profiles': 'Player Profiles',
			'memory': 'Mem',
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
					row.append(service.get_option('RCONPort', True) if service.is_rcon_available() else 'N/A')
				elif col == 'enabled':
					row.append('✅ Enabled' if service.is_enabled() else '❌ Disabled')
				elif col == 'running':
					row.append('✅ Running' if service.is_running() else '❌ Stopped')
				elif col == 'admin_password':
					row.append(service.get_option('ServerAdminPassword'))
				elif col == 'players':
					v = service.rcon_get_number_players()
					row.append(str(v) if v is not None else 'N/A')
				elif col == 'mods':
					row.append(', '.join(service.mods))
				elif col == 'cluster':
					row.append(service.cluster_id or '')
				elif col == 'map_size':
					row.append(str(service.get_map_file_size()))
				elif col == 'player_profiles':
					row.append(str(service.get_num_player_profiles()))
				elif col == 'memory':
					row.append(service.get_memory_usage())
				else:
					row.append('???')

				col_lengths[counter] = max(col_lengths[counter], str_len(row[-1]))
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
				vals.append(str_ljust(row[counter], col_lengths[counter]))
				counter += 1
			print('| %s |' % ' | '.join(vals))


class ModLibrary(object):
	_mods = None

	@classmethod
	def refresh_data(cls):
		"""
		Force refresh of mod data from disk
		:return:
		"""
		ModLibrary._mods = None

	@classmethod
	def get_mods(cls) -> dict:
		if cls._mods is None:
			cls._mods = {}
			# Pull mod data from the JSON library file
			lib_file = os.path.join(here, 'AppFiles', 'ShooterGame', 'Binaries', 'Win64', 'ShooterGame', 'ModsUserData', '83374', 'library.json')
			if os.path.exists(lib_file):
				with open(lib_file, 'r', encoding='utf-8-sig') as f:
					mod_lib = json.load(f)
					for mod in mod_lib['installedMods']:
						cls._mods[str(mod['details']['iD'])] = {
							'name': mod['details']['name'],
							'path': mod['pathOnDisk']
						}

		return cls._mods

	@classmethod
	def resolve_mod_name(cls, mod_id) -> Union[str, None]:
		mods = cls.get_mods()
		if mod_id in mods:
			return mods[mod_id]['name']
		return None


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
				s.rcon_message(time_message)
				players_connected = True
			else:
				# RCON enabled, but no players connected.  GREAT!
				print('Saving %s' % s.session)
				s.rcon_save_world()
				sleep(10)
				print('Shutting down %s' % s.session)
				s.stop()
	return players_connected


def print_error_log(num_lines = 20):
	"""
	Print the last lines of the error log
	:param num_lines: Number of lines (default 20) to display
	:return:
	"""
	log_file = os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Logs', 'ShooterGame.log')
	subprocess.call(['tail', '-n', str(num_lines), log_file], stdout=sys.stdout)


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

	players_connected = _safe_stop_inner(services, Messages.get('shutdown_5min'))

	if players_connected:
		print('Waiting a minute until the next warning (5 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_4min'))

	if players_connected:
		print('Waiting a minute until the next warning (4 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_3min'))

	if players_connected:
		print('Waiting a minute until the next warning (3 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_2min'))

	if players_connected:
		print('Waiting a minute until the next warning (2 minutes remaining)')
		sleep(60)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_1min'))

	if players_connected:
		print('Waiting 30 seconds until the next warning (1 minute remaining)')
		sleep(30)
		players_connected = _safe_stop_inner(services, Messages.get('shutdown_30sec'))

	if players_connected:
		print('Last warning')
		sleep(30)
		_safe_stop_inner(services, Messages.get('shutdown_now'))

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
			start_timer = time()
			print('Starting %s, please wait, may take a minute...' % s.session)
			print('loading................')
			s.start()
			check_counter = 0
			ready = False
			while check_counter < 600:
				check_counter += 1
				# Watch the exit status of the service,
				# if this changes to something other than 0, it indicates a game crash.
				exec_status = int(subprocess.run([
					'systemctl', 'show', '-p', 'ExecMainStatus', s.name
				], stdout=subprocess.PIPE).stdout.decode().strip()[15:])

				if exec_status == 1:
					print_error_log()
					print('❗⛔❗ WARNING - Service has exited with status 1')
					print('This may indicate corrupt files, please check logs and verify files with Steam.')
					return
				elif exec_status == 15:
					print_error_log()
					print('❗⛔❗ WARNING - Service has exited with status 15')
					print('This may indicate that your server ran out of memory.')
					return
				elif exec_status != 0:
					print_error_log()
					print('❗⛔❗ WARNING - Service has exited with status %s' % exec_status)
					return

				if s.get_pid() == 0:
					print_error_log()
					print('❗⛔❗ WARNING - Process has crashed!')
					return

				status_rcon = 'waiting'
				if check_counter >= 120:
					# After a bit of time, start checking if RCON is available.
					# That is the indication that the server is ready.
					if s.is_rcon_available():
						players_connected = s.rcon_get_number_players()
						if players_connected is None:
							status_rcon = '❌'
						else:
							status_rcon = '✅'
							ready = True
					else:
						# RCON is not enabled so we do not know when it's really available.
						status_rcon = '???'
						ready = True

				# Clear the last line status output and provide a new dynamic update
				seconds_elapsed = round(time() - start_timer)
				since_minutes = str(seconds_elapsed // 60)
				since_seconds = seconds_elapsed % 60
				if since_seconds < 10:
					since_seconds = '0' + str(since_seconds)
				else:
					since_seconds = str(since_seconds)
				print(
					'\033[1A\033[K Time: %s, CPU: %s, Memory: %s, RCON: %s' % (
						since_minutes + ':' + since_seconds,
						s.get_cpu_usage(),
						s.get_memory_usage(),
						status_rcon
					)
				)

				if ready:
					discord_alert('map_started', [s.session])
					break

				sleep(0.5)

			if not ready:
				print_error_log()
				print('❗⛔❗ WARNING - Service did not become ready in time, please check logs!')


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
		ModLibrary.refresh_data()

		header('Service Details')
		running = service.is_running()
		if service.is_rcon_available() and running:
			players = service.rcon_get_number_players()
			if players is None:
				players = 'N/A (unable to retrieve player count)'
		else:
			players = 'N/A'

		# Retrieve the WAN IP of this instance; can be useful for direct access.
		req = request.Request('http://wan.eval.bz', headers={'User-Agent': 'ARK-Ascended-Management'}, method='GET')
		try:
			with request.urlopen(req) as resp:
				wan = resp.read().decode('utf-8')
		except urlerror.HTTPError:
			wan = 'N/A'
		except urlerror.URLError:
			wan = 'N/A'
		except json.JSONDecodeError:
			wan = 'N/A'

		print('Map:         %s' % service.map)
		print('Session:     %s' % service.session)
		print('WAN IP:      %s' % wan)
		print('Port:        %s (UDP)' % service.port)
		print('RCON:        %s (TCP)' % service.get_option('RCONPort', True))
		print('Auto-Start:  %s' % ('Yes' if service.is_enabled() else 'No'))
		print('Status:      %s' % ('Running' if running else 'Stopped'))
		print('Players:     %s' % players)
		print('Mods:        %s' % '\n             '.join(service.get_mod_names()))
		print('Cluster ID:  %s' % (service.cluster_id or ''))
		print('Options:     %s' % service.get_options())
		print('Flags:       %s' % service.other_flags)
		if running:
			print('Memory:      %s' % service.get_memory_usage())
			print('CPU:         %s' % service.get_cpu_usage())
			print('Map Size:    %s MB' % service.get_map_file_size())
			connect_pw = service.get_option('ServerPassword')
			if connect_pw == '':
				print('Connect Cmd: open %s:%s' % (wan, service.port))
			else:
				print('Connect Cmd: open %s:%s?%s' % (wan, service.port, connect_pw))
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

		if running:
			print('Map is currently running, please stop to make changes.')
		else:
			options.append('[M]ods | [C]luster | re[N]ame | [F]lags | [O]ptions')

		if running:
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
			print('')
			print('Enter options for this map seperated by a question mark (?).')
			val = rlinput('Enter new options: ', service.get_options()).strip()
			service.set_options(val)
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
		# Pull mod data to know which mods are unused
		ModLibrary.refresh_data()
		mods_installed = ModLibrary.get_mods()
		mods_used = []

		running = False
		for service in services:
			if service.is_running():
				running = True
			for mod in service.mods:
				if mod not in mods_used:
					mods_used.append(mod)
		header('Mods Configuration')
		table = Table(['session', 'mods', 'running'])
		table.render(services)
		print('')

		print('Installed Mods:')
		for mod_id in mods_installed:
			used = ' (In Use)' if mod_id in mods_used else ' (Not In Use)'
			print(' - %s: %s%s' % (mod_id, mods_installed[mod_id]['name'], used))
		print('')
		if running:
			print('⚠️  At least one map is running - unable to change mods while a map is active')
			opt = input('[B]ack: ').lower()
		else:
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
		running = False
		for service in services:
			if service.is_running():
				running = True
		header('Cluster Configuration')
		table = Table(['session', 'cluster', 'running'])
		table.render(services)
		print('')
		if running:
			print('⚠️  At least one map is running - unable to change cluster while a map is active')
			opt = input('[B]ack: ').lower()
		else:
			opt = input('[C]hange cluster id on all maps | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'c' and not running:
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
		running = False
		header('Admin and RCON Configuration')
		table = Table(['session', 'admin_password', 'rcon', 'running'])
		table.render(services)
		for service in services:
			if service.is_running():
				running = True
		print('')

		if running:
			print('⚠️  At least one map is running - unable to change settings while a map is active')
			opt = input('[B]ack: ').lower()
		else:
			opt = input('[C]hange admin password on all | [E]nable RCON on all | [D]isable RCON on all | [B]ack: ').lower()

		if opt == 'b':
			return
		elif opt == 'e' and not running:
			for s in services:
				s.options['RCONEnabled'] = 'True'
				s.save()
		elif opt == 'd' and not running:
			print('WARNING - disabling RCON will prevent clean shutdowns!')
			for s in services:
				s.options['RCONEnabled'] = 'False'
				s.save()
		elif opt == 'c' and not running:
			val = input('Enter new password: ').strip()
			if val:
				for s in services:
					s.options['ServerAdminPassword'] = val.replace('"', '').replace(' ', '')
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
			options.append('[B]ack')
			print(' | '.join(options))
			opt = input(': ').lower()

			if opt == 'b':
				return
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


def menu_messages():
	messages = []
	for key in Messages.messages:
		messages.append((key, Messages.messages[key]['title']))

	while True:
		header('Player Messages')
		print('The following messages will be sent to players when certain events occur.')
		print('')
		counter = 0
		for key, title in messages:
			counter += 1
			print('| %s | %s | %s' % (str(counter).ljust(2), title.ljust(28), Messages.get(key)))

		print('')
		opt = input('[1-%s] change message | [B]ack: ' % counter).lower()
		key = None
		val = ''

		if opt == 'b':
			return
		elif 1 <= int(opt) <= counter:
			key = messages[int(opt)-1][0]
			print('')
			print('Edit the message, left/right works to move cursor.  Blank to use default.')
			val = rlinput('%s: ' % messages[int(opt)-1][1], Messages.get(key)).strip()
		else:
			print('Invalid option')

		if key is not None:
			config['Messages'][key] = val.replace('%', '%%')
			save_config()


def menu_backup_restore():
	while True:
		header('Backups and Restore')
		print('')
		backups = []
		if os.path.exists(os.path.join(here, 'backups')):
			for f in os.listdir(os.path.join(here, 'backups')):
				if f.endswith('.tgz'):
					backups.append(f)
		print('Existing Backups:')
		counter = 0
		for b in backups:
			counter += 1
			backup_size = os.path.getsize(os.path.join(here, 'backups', b))
			backup_size_mb = round(backup_size / (1024 * 1024))
			print('%s - %s (%s MB)' % (counter, b, backup_size_mb))
		if len(backups) == 0:
			print('No backups found')

		print('')
		if len(backups) > 0:
			print('Enter 1-%s to restore a backup' % len(backups))
		print('[N]ew Backup | [B]ack')
		opt = input(': ').lower()

		if opt == 'n':
			print('Creating new backup... please wait a moment')
			subprocess.run([os.path.join(here, 'backup.sh')], stderr=sys.stderr, stdout=sys.stdout)
		elif opt == 'b':
			return
		elif opt.isdigit() and 1 <= int(opt) <= len(backups):
			print('Restoring a backup will overwrite existing game data!  Continue? [y/N]')
			confirm = input(': ').lower()
			if confirm == 'y':
				print('Restoring backup... please wait a moment')
				subprocess.run([os.path.join(here, 'restore.sh'), 'backups/' + backups[int(opt)-1]], stderr=sys.stderr, stdout=sys.stdout)


def menu_wipe():
	while True:
		header('Wipe User Data')
		print('Wiping user data will remove all player progress, including characters, items, and structures.')
		print('This action is irreversible and will reset the game to its initial state.')
		print('')
		table = Table(['num', 'map', 'map_size', 'player_profiles'])
		table.render(services)

		print('')
		print('1-%s to reset individual map' % len(services))
		print('or [A]ll to wipe all user data across all maps, [B]ack to return')
		opt = input(': ').lower()

		if opt == 'b':
			return

		if opt.isdigit() and 1 <= int(opt) <= len(services):
			path = services[int(opt)-1].get_saved_location()
		elif opt == 'a':
			path = os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'SavedArks')
		else:
			print('Invalid option!')
			return

		print('Are you sure you want to proceed? This action cannot be undone! type DELETE to confirm.')
		confirm = input(': ')
		if confirm == 'DELETE':
			# Instead of doing a simple shutil.rmtree, manually walk through the target directory
			# and delete individual files.  This avoids issues with symlinks that may exist in the SavedArks folder.
			for root, dir, files in os.walk(path, followlinks=True):
				for f in files:
					file_path = os.path.join(root, f)
					print('Removing %s...' % file_path)
					os.remove(file_path)
		else:
			print('Wipe operation cancelled.')


def menu_main():
	stay = True
	while stay:
		running = False
		for s in services:
			if s.is_running():
				running = True
		header('Welcome to the ARK Survival Ascended Linux Server Manager')
		print('Find an issue? https://github.com/cdp1337/ARKSurvivalAscended-Linux/issues')
		print('Want to help support this project? https://ko-fi.com/bitsandbytes')
		print('')
		table = Table(['num', 'map', 'session', 'port', 'rcon', 'enabled', 'running', 'memory', 'players'])
		table.render(services)

		print('')
		print('1-%s to manage individual map settings' % len(services))
		print('Configure: [M]ods | [C]luster | [A]dmin password/RCON | re[N]ame | [D]iscord integration | [P]layer messages')
		print('Control: [S]tart all | s[T]op all | [R]estart all | [U]pdate')
		if running:
			print('Manage Data: (please stop all maps to manage game data)')
		else:
			print('Manage Data: [B]ackup/Restore | [W]ipe User Data')
		print('or [Q]uit to exit')
		opt = input(': ').lower()

		if opt == 'a':
			menu_admin_password()
		elif opt == 'b':
			if running:
				print('⚠️  Please stop all maps before managing backups.')
			else:
				menu_backup_restore()
		elif opt == 'c':
			menu_cluster()
		elif opt == 'd':
			menu_discord()
		elif opt == 'm':
			menu_mods()
		elif opt == 'n':
			if running:
				print('⚠️  Please stop all maps before renaming.')
			else:
				val = input('Please enter new name: ').strip()
				if val != '':
					for s in services:
						s.rename(val)
		elif opt == 'p':
			menu_messages()
		elif opt == 'q':
			stay = False
		elif opt == 'r':
			safe_restart(services)
		elif opt == 's':
			safe_start(services)
		elif opt == 't':
			safe_stop(services)
		elif opt == 'u':
			if running:
				print('⚠️ Please stop all maps prior to updating.')
			else:
				subprocess.run([os.path.join(here, 'update.sh')], stderr=sys.stderr, stdout=sys.stdout)
		elif opt == 'w':
			if running:
				print('⚠️  Please stop all maps before wiping user data.')
			else:
				menu_wipe()
		elif opt.isdigit() and 1 <= int(opt) <= len(services):
			menu_service(services[int(opt)-1])

# Get the script configuration, useful for settings not directly related to the game
config = configparser.ConfigParser()
config.read(os.path.join(here, '.settings.ini'))
if 'Discord' not in config.sections():
	config['Discord'] = {}
if 'Messages' not in config.sections():
	config['Messages'] = {}
if 'Manager' not in config.sections():
	config['Manager'] = {}

shared_settings = None
shared_path = os.path.join(here, 'AppFiles', 'ShooterGame', 'Saved', 'Config', 'WindowsServer', 'GameUserSettings.ini')
if os.path.exists(shared_path):
	shared_settings = configparser.ConfigParser(strict=False)
	shared_settings.read(shared_path)
	if 'ServerSettings' not in shared_settings.sections():
		shared_settings['ServerSettings'] = {}

services = []
services_path = os.path.join(here, 'services')
for f in os.listdir(services_path):
	if f.endswith('.conf'):
		services.append(Services(os.path.join(services_path, f)))


parser = argparse.ArgumentParser('manage.py')
parser.add_argument(
	'--service',
	help='Specify the service instance to manage (default: ALL)',
	type=str,
	default='ALL'
)
#parser.add_argument(
#	'--pre-stop',
#	help='Send notifications to game players and Discord and save the world',
#	action='store_true'
#)
parser.add_argument(
	'--stop', '--stop-all',
	help='Stop the game server',
	action='store_true'
)
parser.add_argument(
	'--start', '--start-all',
	help='Start the game server',
	action='store_true'
)
parser.add_argument(
	'--restart',
	help='Restart the game server',
	action='store_true'
)
#parser.add_argument(
#	'--monitor',
#	help='Monitor the game server status in real time',
#	action='store_true'
#)
parser.add_argument(
	'--backup',
	help='Backup the game server files',
	action='store_true'
)
#parser.add_argument(
#	'--restore',
#	help='Restore the game server files from a backup archive',
#	type=str,
#	default=''
#)
#parser.add_argument(
#	'--check-update',
#	help='Check for game updates via SteamCMD and report the status',
#	action='store_true'
#)
parser.add_argument(
	'--get-services',
	help='List the available service instances for this game',
	action='store_true'
)
parser.add_argument(
	'--is-running',
	help='Check if any game service is currently running (exit code 0 = yes, 1 = no)',
	action='store_true'
)
args = parser.parse_args()

if args.service != 'ALL':
	# User opted to manage only a single game instance
	service_to_manage = None
	for s in services:
		if s.name == args.service:
			service_to_manage = s
			break

	if service_to_manage is None:
		print('Service instance %s not found!' % args.service, file=sys.stderr)
		sys.exit(1)
	services = [service_to_manage]

if args.stop:
	safe_stop(services)
elif args.backup:
	# Stop all services prior to backup
	safe_stop(services)
	# Run the backup procedure
	subprocess.run([os.path.join(here, 'backup.sh')], stderr=sys.stderr, stdout=sys.stdout)
	# Start all enabled service
	safe_start(services)
elif args.start:
	safe_start(services)
elif args.restart:
	safe_stop(services)
	safe_start(services)
elif args.is_running:
	exit_code = 1
	for s in services:
		if s.is_running():
			print('%s is running' % s.session)
			exit_code = 0
	sys.exit(exit_code)
elif args.get_services:
	stats = {}
	for s in services:
		svc_stats = {
			'service': s.name,
			'name': s.session,
			'ip': 'N/A',
			'port': s.port,
			'status': 'running' if s.is_running() else 'stopped',
			'player_count': s.rcon_get_number_players(),
			'max_players': s.get_option('MaxPlayers') or 70,
			'memory_usage': s.get_memory_usage(),
			'cpu_usage': s.get_cpu_usage(),
			'game_pid': s.get_game_pid(),
			'service_pid': s.get_pid()
		}
		stats[s.name] = svc_stats
	print(json.dumps(stats))
else:
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
