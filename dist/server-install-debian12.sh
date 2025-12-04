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
#   --reset-proton  - Reset proton directories back to default
#   --force-reinstall  - Force a reinstall of the game binaries, mods, and engine
#   --uninstall  - Uninstall the game server
#   --install-custom-map  - Install a custom map (in addition to the defaults)
#   --custom-map-id=<int> - Mod ID of the custom map to install (use with --install-custom-map) OPTIONAL
#   --custom-map-name=<string> - Map Name of the custom map to install, refer to Curseforge description page (use with --install-custom-map) OPTIONAL
#   --dir=<string> - Use a custom installation directory instead of the default OPTIONAL
#   --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
#   --skip-firewall  - Skip installing/configuring the firewall
#   --new-format  - Use the new save format (Nitrado/Official server compatible) OPTIONAL
#
# Changelog:
#   202511XX - Support custom installation directory
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

INSTALLER_VERSION="v20251105~DEV"
# https://github.com/GloriousEggroll/proton-ge-custom
PROTON_VERSION="10-25"
WARLOCK_GUID="0c2de651-ec30-d4ac-c53f-ebdb67398324"
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
    --reset-proton  - Reset proton directories back to default
    --force-reinstall  - Force a reinstall of the game binaries, mods, and engine
    --uninstall  - Uninstall the game server
    --install-custom-map  - Install a custom map (in addition to the defaults)
    --custom-map-id=<int> - Mod ID of the custom map to install (use with --install-custom-map) OPTIONAL
    --custom-map-name=<string> - Map Name of the custom map to install, refer to Curseforge description page (use with --install-custom-map) OPTIONAL
    --dir=<string> - Use a custom installation directory instead of the default OPTIONAL
    --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
    --skip-firewall  - Skip installing/configuring the firewall
    --new-format  - Use the new save format (Nitrado/Official server compatible) OPTIONAL

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
CUSTOM_MAP_ID=""
CUSTOM_MAP_NAME=""
OPT_OVERRIDE_DIR=""
NONINTERACTIVE=0
OPT_SKIP_FIREWALL=0
OPT_NEWFORMAT=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		--reset-proton) OPT_RESET_PROTON=1; shift 1;;
		--force-reinstall) OPT_FORCE_REINSTALL=1; shift 1;;
		--uninstall) OPT_UNINSTALL=1; shift 1;;
		--install-custom-map) OPT_INSTALL_CUSTOM_MAP=1; shift 1;;
		--custom-map-id=*)
			CUSTOM_MAP_ID="${1#*=}";
			[ "${CUSTOM_MAP_ID:0:1}" == "'" ] && [ "${CUSTOM_MAP_ID:0-1}" == "'" ] && CUSTOM_MAP_ID="${CUSTOM_MAP_ID:1:-1}"
			[ "${CUSTOM_MAP_ID:0:1}" == '"' ] && [ "${CUSTOM_MAP_ID:0-1}" == '"' ] && CUSTOM_MAP_ID="${CUSTOM_MAP_ID:1:-1}"
			shift 1;;
		--custom-map-name=*)
			CUSTOM_MAP_NAME="${1#*=}";
			[ "${CUSTOM_MAP_NAME:0:1}" == "'" ] && [ "${CUSTOM_MAP_NAME:0-1}" == "'" ] && CUSTOM_MAP_NAME="${CUSTOM_MAP_NAME:1:-1}"
			[ "${CUSTOM_MAP_NAME:0:1}" == '"' ] && [ "${CUSTOM_MAP_NAME:0-1}" == '"' ] && CUSTOM_MAP_NAME="${CUSTOM_MAP_NAME:1:-1}"
			shift 1;;
		--dir=*)
			OPT_OVERRIDE_DIR="${1#*=}";
			[ "${OPT_OVERRIDE_DIR:0:1}" == "'" ] && [ "${OPT_OVERRIDE_DIR:0-1}" == "'" ] && OPT_OVERRIDE_DIR="${OPT_OVERRIDE_DIR:1:-1}"
			[ "${OPT_OVERRIDE_DIR:0:1}" == '"' ] && [ "${OPT_OVERRIDE_DIR:0-1}" == '"' ] && OPT_OVERRIDE_DIR="${OPT_OVERRIDE_DIR:1:-1}"
			shift 1;;
		--non-interactive) NONINTERACTIVE=1; shift 1;;
		--skip-firewall) OPT_SKIP_FIREWALL=1; shift 1;;
		--new-format) OPT_NEWFORMAT=1; shift 1;;
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
# Downloads the file to a temp location initially, then moves it to the final destination
# upon a successful download to avoid partial files.
#
# Returns 0 on success, 1 on failure
#
# CHANGELOG:
#   2025.11.23 - Download to a temp location to verify download was successful
#              - use which -s for cleaner checks
#   2025.11.09 - Initial version
#
function download() {
	local SOURCE="$1"
	local DESTINATION="$2"
	local TMP=$(mktemp)

	if [ -z "$SOURCE" ] || [ -z "$DESTINATION" ]; then
		echo "download: Missing required parameters!" >&2
		return 1
	fi

	if which -s curl; then
		if curl -fsL "$SOURCE" -o "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif which -s wget; then
		if wget -q "$SOURCE" -O "$TMP"; then
			mv $TMP "$DESTINATION"
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
#
# CHANGELOG:
#   2025.11.23 - Use download scriptlet for downloading
#   2024.12.22 - Initial version
#
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
#
# CHANGELOG:
#   2025.04.10 - Switch from "systemctl list-unit-files" to "which" to support older systems
function get_available_firewall() {
	if which -s firewall-cmd; then
		echo "firewalld"
	elif which -s ufw; then
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
		download http://repo.steampowered.com/steam/archive/stable/steam.gpg /usr/share/keyrings/steam.gpg
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
#
# CHANGELOG:
#   2025.04.10 - Set Debian frontend to noninteractive
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
		DEBIAN_FRONTEND="noninteractive" apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
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
#   --proto <tcp|udp>   Protocol to allow (alternative method)
#   --comment <comment> (only UFW) Comment for the rule
#
# Specify multiple ports with `--port '#,#,#'` or a range `--port '#:#'`
#
# CHANGELOG:
#   2025.11.23 - Use return codes instead of exit to allow the caller to handle errors
#   2025.04.10 - Add "--proto" argument as alternative to "--tcp|--udp"
#
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
			--proto)
				shift
				PROTO=$1
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
		return 2
	fi

	if [ "$PORT" != "" -a "$ZONE" == "trusted" ]; then
		echo "firewall_allow: Trusted zones do not use ports!" >&2
		return 2
	fi

	if [ "$ZONE" == "trusted" -a "$SOURCE" == "any" ]; then
		echo "firewall_allow: Trusted zones require a source!" >&2
		return 2
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
		return 0
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
		return 0
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
		return 0
	elif [ "$FIREWALL" == "none" ]; then
		echo "firewall_allow: No firewall detected" >&2
		return 1
	else
		echo "firewall_allow: Unsupported or unknown firewall" >&2
		echo 'Please report this at https://github.com/cdp1337/ScriptsCollection/issues' >&2
		return 1
	fi
}
##
# Generate a random password, (using characters that are easy to read and type)
function random_password() {
	< /dev/urandom tr -dc _cdefhjkmnprtvwxyACDEFGHJKLMNPQRTUVWXY2345689 | head -c${1:-24};echo;
}
##
# Determine if the current shell session is non-interactive.
#
# Checks NONINTERACTIVE, CI, DEBIAN_FRONTEND, TERM, and TTY status.
#
# Returns 0 (true) if non-interactive, 1 (false) if interactive.
#
# CHANGELOG:
#   2025.11.23 - Initial version
#
function is_noninteractive() {
	# explicit flags
	case "${NONINTERACTIVE:-}${CI:-}" in
		1*|true*|TRUE*|True*|*CI* ) return 0 ;;
	esac

	# debian frontend
	if [ "${DEBIAN_FRONTEND:-}" = "noninteractive" ]; then
		return 0
	fi

	# dumb terminal or no tty on stdin/stdout
	if [ "${TERM:-}" = "dumb" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
		return 0
	fi

	return 1
}

##
# Prompt user for a text response
#
# Arguments:
#   --default="..."   Default text to use if no response is given
#
# Returns:
#   text as entered by user
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.01.01 - Initial version
#
function prompt_text() {
	local DEFAULT=""
	local PROMPT="Enter some text"
	local RESPONSE=""

	while [ $# -ge 1 ]; do
		case $1 in
			--default=*) DEFAULT="${1#*=}";;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	echo -n '> : ' >&2

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		echo $DEFAULT
		return
	fi

	read RESPONSE
	if [ "$RESPONSE" == "" ]; then
		echo "$DEFAULT"
	else
		echo "$RESPONSE"
	fi
}

##
# Prompt user for a yes or no response
#
# Arguments:
#   --invert            Invert the response (yes becomes 0, no becomes 1)
#   --default-yes       Default to yes if no response is given
#   --default-no        Default to no if no response is given
#   -q                  Quiet mode (no output text after response)
#
# Returns:
#   1 for yes, 0 for no (or inverted if --invert is set)
#
# CHANGELOG:
#   2025.11.23 - Use is_noninteractive to handle non-interactive mode
#   2025.11.09 - Add -q (quiet) option to suppress output after prompt (and use return value)
#   2025.01.01 - Initial version
#
function prompt_yn() {
	local TRUE=0 # Bash convention: 0 is success/true
	local YES=1
	local FALSE=1 # Bash convention: non-zero is failure/false
	local NO=0
	local DEFAULT="n"
	local DEFAULT_CODE=1
	local PROMPT="Yes or no?"
	local RESPONSE=""
	local QUIET=0

	while [ $# -ge 1 ]; do
		case $1 in
			--invert) YES=0; NO=1 TRUE=1; FALSE=0;;
			--default-yes) DEFAULT="y";;
			--default-no) DEFAULT="n";;
			-q) QUIET=1;;
			*) PROMPT="$1";;
		esac
		shift
	done

	echo "$PROMPT" >&2
	if [ "$DEFAULT" == "y" ]; then
		DEFAULT="$YES"
		DEFAULT_CODE=$TRUE
		echo -n "> (Y/n): " >&2
	else
		DEFAULT="$NO"
		DEFAULT_CODE=$FALSE
		echo -n "> (y/N): " >&2
	fi

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		if [ $QUIET -eq 0 ]; then
			echo $DEFAULT
		fi
		return $DEFAULT_CODE
	fi

	read RESPONSE
	case "$RESPONSE" in
		[yY]*)
			if [ $QUIET -eq 0 ]; then
				echo $YES
			fi
			return $TRUE;;
		[nN]*)
			if [ $QUIET -eq 0 ]; then
				echo $NO
			fi
			return $FALSE;;
		*)
			if [ $QUIET -eq 0 ]; then
				echo $DEFAULT
			fi
			return $DEFAULT_CODE;;
	esac
}
##
# Print a header message
#
# CHANGELOG:
#   2025.11.09 - Port from _common to bz_eval_tui
#   2024.12.25 - Initial version
#
function print_header() {
	local header="$1"
	echo "================================================================================"
	printf "%*s\n" $(((${#header}+80)/2)) "$header"
    echo ""
}


##
# Install the management script from the project's repo
#
# Expects the following variables:
#   GAME_USER    - User account to install the game under
#   GAME_DIR     - Directory to install the game into
#
function install_management() {
	print_header "Performing install_management"

	# Install management console and its dependencies
	local SRC=""

	if [[ "$INSTALLER_VERSION" == *"~DEV"* ]]; then
		# Development version, pull from dev branch
		SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/dev/dist/manage.py"
	else
		# Stable version, pull from tagged release
		SRC="https://raw.githubusercontent.com/${REPO}/refs/tags/${INSTALLER_VERSION}/dist/manage.py"
	fi

	if ! download "$SRC" "$GAME_DIR/manage.py"; then
    		# Fallback to main branch
    		SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/main/dist/manage.py"
    		if ! download "$SRC" "$GAME_DIR/manage.py"; then
    			echo "Could not download management script!" >&2
    			exit 1
    		fi
    	fi

	chown $GAME_USER:$GAME_USER "$GAME_DIR/manage.py"
	chmod +x "$GAME_DIR/manage.py"

	# Install configuration definitions
	cat > "$GAME_DIR/configs.yaml" <<EOF
manager:
  - name: Shutdown Warning 5 Minutes
    section: Messages
    key: shutdown_5min
    type: str
    default: Server is shutting down in 5 minutes
    help: "Custom message broadcasted to players 5 minutes before server shutdown."
  - name: Shutdown Warning 4 Minutes
    section: Messages
    key: shutdown_4min
    type: str
    default: Server is shutting down in 4 minutes
    help: "Custom message broadcasted to players 4 minutes before server shutdown."
  - name: Shutdown Warning 3 Minutes
    section: Messages
    key: shutdown_3min
    type: str
    default: Server is shutting down in 3 minutes
    help: "Custom message broadcasted to players 3 minutes before server shutdown."
  - name: Shutdown Warning 2 Minutes
    section: Messages
    key: shutdown_2min
    type: str
    default: Server is shutting down in 2 minutes
    help: "Custom message broadcasted to players 2 minutes before server shutdown."
  - name: Shutdown Warning 1 Minute
    section: Messages
    key: shutdown_1min
    type: str
    default: Server is shutting down in 1 minute
    help: "Custom message broadcasted to players 1 minute before server shutdown."
  - name: Shutdown Warning 30 Seconds
    section: Messages
    key: shutdown_30sec
    type: str
    default: Server is shutting down in 30 seconds!
    help: "Custom message broadcasted to players 30 seconds before server shutdown."
  - name: Shutdown Warning NOW
    section: Messages
    key: shutdown_now
    type: str
    default: Server is shutting down NOW!
    help: "Custom message broadcasted to players immediately before server shutdown."
  - name: Map Started (Discord)
    section: Messages
    key: map_started
    type: str
    default: "{instance} has started! :rocket:"
    help: "Custom message sent to Discord when the server starts, use '{instance}' to insert the map name"
  - name: Map Stopping (Discord)
    section: Messages
    key: map_stopping
    type: str
    default: ":small_red_triangle_down: {instance} is shutting down"
    help: "Custom message sent to Discord when the server stops, use '{instance}' to insert the map name"
  - name: Joined Session Name
    section: Manager
    key: joinedsessionname
    type: bool
    default: true
    help: "Enables joining the map name to the session name when viewing in the server browser."
  - name: Discord Enabled
    section: Discord
    key: enabled
    type: bool
    default: false
    help: "Enables or disables Discord integration for server status updates."
  - name: Discord Webhook URL
    section: Discord
    key: webhook
    type: str
    help: "The webhook URL for sending server status updates to a Discord channel."
cli:
  - name: Session Name
    section: option
    key: SessionName
    type: str
    help: "Set the name of the server session as it appears in the server browser."
  - name: Alt Save Directory
    section: option
    key: AltSaveDirectoryName
    type: str
    help: "Specify an alternative save directory for server data."
  - name: Always Tick Dedicated Skeletal Meshes
    section: flag
    key: AlwaysTickDedicatedSkeletalMeshes
    type: bool
    help: "Optimize performance by always ticking skeletal meshes on dedicated servers."
  - name: Auto Destroy Structures
    section: flag
    key: AutoDestroyStructures
    type: bool
    help: "Enables auto destruction of old structures."
  - name: Culture
    section: flag
    key: culture
    type: str
    help: "Set the culture for the server (e.g., en-US)."
  - name: Custom Cosmetic Validation
    section: flag
    key: DoCustomCosmeticValidation
    type: bool
    help: "Enables validation of custom cosmetic mods."
  - name: Disable Custom Cosmetics
    section: flag
    key: DisableCustomCosmetics
    type: bool
    help: Disables the Custom Cosmetic system (allowing players to use and display special mods that should only be skins and will be downloaded automatically by the connected clients).
  - name: Disabled Net Range Scaling
    section: flag
    key: disabledinonetrangescaling
    type: bool
    help: Disables creature's network replication range optimization.
  - name: Easter Colors
    section: flag
    key: EasterColors
    type: bool
    help: Chance for Easter colors when creatures spawn.
  - name: Exclusive Join
    section: flag
    key: exclusivejoin
    type: bool
    help: Activate a whitelist only mode on the server, allowing players to join if added to the allow list.
  - name: Force Allow Cave Flyers
    section: flag
    key: ForceAllowCaveFlyers
    type: bool
    help: Force flyer creatures to be allowed into caves
  - name: Force Respawn Dinos
    section: flag
    key: ForceRespawnDinos
    type: bool
    help: Launch with this command to destroy all wild creatures on server start-up.
  - name: GB Usage To Force Restart
    section: flag
    key: GBUsageToForceRestart
    type: int
    default: 35
    help: "Set the memory usage threshold (in GB) to trigger an automatic server restart."
  - name: New Save Format
    section: flag
    key: newsaveformat
    type: bool
    help: Enables the new save format for server saves, improving performance and compatibility with future updates.
  - name: Mods
    section: flag
    key: mods
    type: str
    help: Specifies CurseForge Mod Project IDs. Mods are updated automatically when starting the server.
  - name: No BattlEye
    section: flag
    key: NoBattlEye
    type: bool
    help: Disables BattlEye anti-cheat on the server.
  - name: No Dinos
    section: flag
    key: NoDinos
    type: bool
    help: Launch with this command to prevent any wild creatures from spawning on the server.
  - name: No Wild Babies
    section: flag
    key: NoWildBabies
    type: bool
    help: Launch with this command to prevent wild baby creatures from spawning on the server.
  - name: Passive Mods
    section: flag
    key: passivemods
    type: str
    help: This option disables a mod's functionality while still loading its data. This is useful if, for example, you want to have S-Dinos on Astraeos in your cluster but prevent them from spawning on The Island while still allowing them to be transferred back and forth.
  - name: Port
    section: flag
    key: port
    type: int
    default: 7777
    help: "Set the main port for game connections."
  - name: Server Game Log
    section: flag
    key: servergamelog
    type: bool
    help: Enable server admin logs (including support in the RCON).
  - name: Server Game Log Include Tribe Logs
    section: flag
    key: servergamelogincludetribelogs
    type: bool
    help: Include tribe logs in the server admin logs.
  - name: Server RCON Output Tribe Logs
    section: flag
    key: ServerRCONOutputTribeLogs
    type: bool
    help: Output tribe logs to RCON.
  - name: Server Use Event Colors
    section: flag
    key: ServerUseEventColors
    type: bool
    help: Enable special event colors for creatures spawned during events.
  - name: Stasis Keep Controllers
    section: flag
    key: StasisKeepControllers
    type: bool
    help: Keep AI controllers active while creatures are in stasis.
  - name: Use Dynamic Config
    section: flag
    key: UseDynamicConfig
    type: bool
    help: Enables the use of dynamic configuration files for server settings.
  - name: Use Store
    section: flag
    key: usestore
    type: bool
    help: "Same basic behaviour of official (non-legacy) servers on handling player characters data: character profile file (.arkprofile) is not saved separately from map save (.ark), nor its backup."
  - name: Win Live Max Players
    section: flag
    key: WinLiveMaxPlayers
    type: int
    default: 70
    help: "Set the maximum number of players."
  - name: Cluster ID
    section: flag
    key: clusterid
    type: str
    help: "Set the Cluster ID for server clustering."
  - name: No Transfer From Filtering
    section: flag
    key: NoTransferFromFiltering
    type: bool
    help: "Prevents ARK Data usage between single player and servers who do not have a cluster ID."
  - name: Convert To Store
    section: flag
    key: converttostore
    type: bool
    help: "Converts legacy save files to the store format on server save."
  - name: Custom Notification URL
    section: flag
    key: CustomNotificationURL
    type: str
    help: "Allows server custom notification broadcast using the server message feature. Supports HTTP protocols only (HTTPS is not supported)."
  - name: Disable Character Tracker
    section: flag
    key: disableCharacterTracker
    type: bool
    help: "Used to disable character tracking."
  - name: Disable Dupe Log Deletes
    section: flag
    key: DisableDupeLogDeletes
    type: bool
    help: "Prevents -ForceDupeLog to take effect."
  - name: Force Dupe Log
    section: flag
    key: ForceDupeLog
    type: bool
    help: "Forces dupe logs. Requires -DisableDupeLogDeletes to be not set, enabled behaviour on official."
  - name: Force Use Performance Threads
    section: flag
    key: forceuseperfthreads
    type: bool
    help: "Forces the use of performance threads for better server performance."
  - name: Ignore Duped Items
    section: flag
    key: ignoredupeditems
    type: bool
    help: "If a duped item is detected in an inventory, this will be ignored and not removed."
  - name: No AI
    section: flag
    key: NoAI
    type: bool
    help: "This will disable adding AI controller to creatures."
  - name: No Dinos Except Forced Spawn
    section: flag
    key: NoDinosExceptForcedSpawn
    type: bool
    help: "Prevents wild creatures from being spawned, except for forced spawns. You cannot use this option if -NoDinos is used. Enabling this option will make the following options unusable: -NoDinosExceptStreamingSpawn, -NoDinosExceptManualSpawn and -NoDinosExceptWaterSpawn."
  - name: No Dinos Except Streaming Spawn
    section: flag
    key: NoDinosExceptStreamingSpawn
    type: bool
    help: "Prevents wild creatures from being spawned, except for streaming spawns. You cannot use this option if one of the following options is used: -NoDinos or -NoDinosExceptForcedSpawn. Enabling this option will make the following options unusable: -NoDinosExceptManualSpawn and -NoDinosExceptWaterSpawn."
  - name: No Dinos Except Manual Spawn
    section: flag
    key: NoDinosExceptManualSpawn
    type: bool
    help: "Prevents wild creatures from being spawned, except for manual spawns. You cannot use this option if one of the following options is used: -NoDinos, -NoDinosExceptForcedSpawn or -NoDinosExceptStreamingSpawn. Enabling this option will make option -NoDinosExceptWaterSpawn unusable."
  - name: No Dinos Except Water Spawn
    section: flag
    key: NoDinosExceptWaterSpawn
    type: bool
    help: "Prevents wild creatures from being spawned, except for water spawns. You cannot use this option if one of the following options is used: -NoDinos, -NoDinosExceptForcedSpawn, -NoDinosExceptStreamingSpawn or -NoDinosExceptManualSpawn."
  - name: No Performance Threads
    section: flag
    key: noperfthreads
    type: bool
    help: "Disables the use of performance threads."
  - name: No Sound
    section: flag
    key: nosound
    type: bool
    help: "Disables sound processing on the server."
  - name: One Thread
    section: flag
    key: onethread
    type: bool
    help: "Runs the server using a single thread for all processing."
  - name: Server Platform
    section: flag
    key: ServerPlatform
    type: str
    default: "ALL"
    help: "Allows the server to accept specified platforms. Options are PC for Steam, PS5 for PlayStation 5, XSX for XBOX, WINGDK for Microsoft Store, ALL for crossplay between PC (Steam and Windows Store) and all consoles."
  - name: Unstasis Dino Obstruction Check
    section: flag
    key: UnstasisDinoObstructionCheck
    type: bool
    help: "Should prevent creatures from ghosting through meshes/structures on re-render."
  - name: Use Server Net Speed Check
    section: flag
    key: UseServerNetSpeedCheck
    type: bool
    help: "It should avoid players to accumulate too much movements data per server tick, discarding the last if those are too many."
  - name: Difficulty Offset
    section: option
    key: DifficultyOffset
    type: float
    default: 1.0
    help: "Sets the difficulty offset for the server, affecting wild creature levels."
  - name: RCON Port
    section: option
    key: RCONPort
    type: int
    default: 27020
    help: "Sets the port for RCON (Remote Console) connections."
  - name: RCON Enabled
    section: option
    key: RCONEnabled
    type: bool
    default: false
    help: "Enables or disables RCON (Remote Console) access to the server."
  - name: Server Admin Password
    section: option
    key: ServerAdminPassword
    type: str
    help: "Sets the password for server admin access via RCON."
  - name: Server Hardcore
    section: option
    key: ServerHardcore
    type: bool
    default: false
    help: "Enables hardcore mode on the server, where players have only one life."
  - name: Server Password
    section: option
    key: ServerPassword
    type: str
    help: "Sets a password required for players to join the server."
  - name: Server PVE
    section: option
    key: serverPVE
    type: bool
    default: false
    help: "Enables Player vs Environment mode on the server, disabling player vs player combat."
  - name: XP Multiplier
    section: option
    key: XPMultiplier
    type: float
    default: 1.0
    help: "Sets the experience points multiplier for players on the server."
gus:
  - key: ActiveMods
    section: ServerSettings
    name: Active Mods
    help: List of mod IDs, comma-separated (no spaces). Order sets priority (left-most highest).
  - key: ActiveMapMod
    section: ServerSettings
    name: Active Map Mod
    help: Mod ID of the currently active mod map.
  - key: AdminLogging
    section: ServerSettings
    name: Admin Logging
    help: If true, logs all admin commands to in-game chat.
    type: bool
    default: false
  - key: AllowAnyoneBabyImprintCuddle
    section: ServerSettings
    name: Allow Anyone Baby Imprint Cuddle
    help: If true, allows anyone to cuddle/imprint baby creatures (not only the imprinter).
    type: bool
    default: false
  - key: AllowCaveBuildingPvE
    section: ServerSettings
    name: Allow Cave Building PvE
    help: If true, allows building in caves when PvE mode is enabled.
    type: bool
    default: false
  - key: AllowCaveBuildingPvP
    section: ServerSettings
    name: Allow Cave Building PvP
    help: If false, prevents building in caves when PvP mode is enabled.
    type: bool
    default: true
  - key: AllowCryoFridgeOnSaddle
    section: ServerSettings
    name: Allow Cryo Fridge On Saddle
    help: If true, allows cryofridges on platform saddles and rafts.
    type: bool
    default: false
  - key: AllowFlyerCarryPvE
    section: ServerSettings
    name: Allow Flyer Carry PvE
    help: If true, allows flyers to pick up wild creatures in PvE.
    type: bool
    default: false
  - key: AllowHideDamageSourceFromLogs
    section: ServerSettings
    name: Allow Hide Damage Source From Logs
    help: If false, damage sources are shown in tribe logs.
    type: bool
    default: true
  - key: AllowHitMarkers
    section: ServerSettings
    name: Allow Hit Markers
    help: If false, disables optional ranged attack hit markers.
    type: bool
    default: true
  - key: AllowMultipleAttachedC4
    section: ServerSettings
    name: Allow Multiple Attached C4
    help: If true, allows attaching more than one C4 per creature.
    type: bool
    default: false
  - key: AllowRaidDinoFeeding
    section: ServerSettings
    name: Allow Raid Dino Feeding
    help: If true, allows Titanosaurs to be fed permanently (permanent tame).
    type: bool
    default: false
  - key: AllowThirdPersonPlayer
    section: ServerSettings
    name: Allow Third Person Player
    help: If false, disables third-person camera on dedicated servers.
    type: bool
    default: true
  - key: AlwaysAllowStructurePickup
    section: ServerSettings
    name: Always Allow Structure Pickup
    help: If true, disables the quick pick-up timer.
    type: bool
    default: false
  - key: ArmadoggoDeathCooldown
    section: ServerSettings
    name: Armadoggo Death Cooldown
    help: Seconds until Armadoggo can reappear after fatal damage.
    type: int
    default: 3600
  - key: AutoSavePeriodMinutes
    section: ServerSettings
    name: Auto Save Period Minutes
    help: Interval for automatic saves in minutes (0 = constant saving).
    type: float
    default: 15.0
  - key: BanListURL
    section: ServerSettings
    name: Ban List URL
    help: |
      URL to the global ban list (official ASA: https://cdn2.arkdedicated.com/asa/BanList.txt).
  - key: ClampItemSpoilingTimes
    section: ServerSettings
    name: Clamp Item Spoiling Times
    help: If true, clamps spoiling times to items' max spoiling times.
    type: bool
    default: false
  - key: ClampResourceHarvestDamage
    section: ServerSettings
    name: Clamp Resource Harvest Damage
    help: If true, limits harvest damage based on resource remaining health.
    type: bool
    default: false
  - key: CosmeticWhitelistOverride
    section: ServerSettings
    name: Cosmetic Whitelist Override
    help: URL to a comma-separated list of whitelisted custom cosmetics (special format).
  - key: CosmoWeaponAmmoReloadAmount
    section: ServerSettings
    name: Cosmo Weapon Ammo Reload Amount
    help: Amount of ammo given when Cosmo's webslinger reloads over time.
    type: int
    default: 1
  - key: CustomLiveTuningUrl
    section: ServerSettings
    name: Custom Live Tuning URL
    help: Direct link to the live tuning JSON file (overrides live tuning).
  - key: DayCycleSpeedScale
    section: ServerSettings
    name: Day Cycle Speed Scale
    help: Scaling factor for passage of time (day/night cycle). 1.0 is default.
    type: float
    default: 1.0
  - key: DayTimeSpeedScale
    section: ServerSettings
    name: Day Time Speed Scale
    help: Scaling factor for day-time speed relative to night.
    type: float
    default: 1.0
  - key: DifficultyOffset
    section: ServerSettings
    name: Difficulty Offset
    help: Server difficulty multiplier.
    type: float
    default: 1.0
  - key: DinoCharacterFoodDrainMultiplier
    section: ServerSettings
    name: Dino Character Food Drain Multiplier
    help: Scaling for creature food consumption (taming also affected).
    type: float
    default: 1.0
  - key: DinoCharacterHealthRecoveryMultiplier
    section: ServerSettings
    name: Dino Character Health Recovery Multiplier
    help: Scaling for creature health recovery.
    type: float
    default: 1.0
  - key: DinoCharacterStaminaDrainMultiplier
    section: ServerSettings
    name: Dino Character Stamina Drain Multiplier
    help: Scaling for creature stamina consumption.
    type: float
    default: 1.0
  - key: DinoDamageMultiplier
    section: ServerSettings
    name: Dino Damage Multiplier
    help: Scaling for damage wild creatures deal.
    type: float
    default: 1.0
  - key: DinoResistanceMultiplier
    section: ServerSettings
    name: Dino Resistance Multiplier
    help: Scaling for resistance wild creatures have to incoming damage.
    type: float
    default: 1.0
  - key: DestroyTamesOverTheSoftTameLimit
    section: ServerSettings
    name: Destroy Tames Over The Soft Tame Limit
    help: If true, marks/destroys dinos above the soft tame limit.
    type: bool
    default: false
  - key: DisableCryopodEnemyCheck
    section: ServerSettings
    name: Disable Cryopod Enemy Check
    help: If true, allows cryopods to be used while enemies are nearby.
    type: bool
    default: false
  - key: DisableCryopodFridgeRequirement
    section: ServerSettings
    name: Disable Cryopod Fridge Requirement
    help: If true, allows cryopods without a powered cryofridge nearby.
    type: bool
    default: false
  - key: DisableDinoDecayPvE
    section: ServerSettings
    name: Disable Dino Decay PvE
    help: If true, disables creature decay in PvE mode.
    type: bool
    default: false
  - key: DisableImprintDinoBuff
    section: ServerSettings
    name: Disable Imprint Dino Buff
    help: If true, disables the imprinting stat bonus for imprinted creatures.
    type: bool
    default: false
  - key: DisablePvEGamma
    section: ServerSettings
    name: Disable PvE Gamma
    help: If true, prevents use of "gamma" console command in PvE.
    type: bool
    default: false
  - key: DisableStructureDecayPvE
    section: ServerSettings
    name: Disable Structure Decay PvE
    help: If true, disables gradual auto-decay of player structures.
    type: bool
    default: false
  - key: DisableWeatherFog
    section: ServerSettings
    name: Disable Weather Fog
    help: If true, disables fog.
    type: bool
    default: false
  - key: DontAlwaysNotifyPlayerJoined
    section: ServerSettings
    name: Dont Always Notify Player Joined
    help: If true, disables player join notifications globally.
    type: bool
    default: false
  - key: EnableExtraStructurePreventionVolumes
    section: ServerSettings
    name: Enable Extra Structure Prevention Volumes
    help: If true, prevents building in certain resource-rich areas.
    type: bool
    default: false
  - key: EnablePvPGamma
    section: ServerSettings
    name: Enable PvP Gamma
    help: If true, allows "gamma" console command in PvP.
    type: bool
    default: false
  - key: ForceAllStructureLocking
    section: ServerSettings
    name: Force All Structure Locking
    help: If true, defaults all structures to locked.
    type: bool
    default: false
  - key: ForceGachaUnhappyInCaves
    section: ServerSettings
    name: Force Gacha Unhappy In Caves
    help: If true, Gachas become unhappy inside caves.
    type: bool
    default: true
  - key: globalVoiceChat
    section: ServerSettings
    name: Global Voice Chat
    help: If true, voice chat is global.
    type: bool
    default: false
  - key: HarvestAmountMultiplier
    section: ServerSettings
    name: Harvest Amount Multiplier
    help: Scaling for harvested resource yields.
    type: float
    default: 1.0
  - key: HarvestHealthMultiplier
    section: ServerSettings
    name: Harvest Health Multiplier
    help: Scaling for resource "health" (how many strikes it survives).
    type: float
    default: 1.0
  - key: IgnoreLimitMaxStructuresInRangeTypeFlag
    section: ServerSettings
    name: Ignore Limit Max Structures In Range Type Flag
    help: If true, removes the 150 decorative-structures limit (flags, signs, etc.).
    type: bool
    default: false
  - key: ImplantSuicideCD
    section: ServerSettings
    name: Implant Suicide CD
    help: Seconds between uses of implant's respawn feature.
    type: int
    default: 28800
  - key: ItemStackSizeMultiplier
    section: ServerSettings
    name: Item Stack Size Multiplier
    help: Multiplies default item stack sizes (items with stack size 1 unaffected).
    type: float
    default: 1.0
  - key: KickIdlePlayersPeriod
    section: ServerSettings
    name: Kick Idle Players Period
    help: Seconds of inactivity before idle-kick (requires command-line flag).
    type: float
    default: 3600.0
  - key: MaxCosmoWeaponAmmo
    section: ServerSettings
    name: Max Cosmo Weapon Ammo
    help: Max ammo for Cosmo webslinger (-1 = scale with level).
    type: int
    default: -1
  - key: MaxPersonalTamedDinos
    section: ServerSettings
    name: Max Personal Tamed Dinos
    help: Per-tribe creature tame limit (0 disables per-tribe limit).
    type: int
    default: 0
  - key: MaxTamedDinos
    section: ServerSettings
    name: Max Tamed Dinos
    help: Global cap on tamed creatures (suggest integer, code uses float).
    type: float
    default: 5000.0
  - key: MaxTamedDinos_SoftTameLimit
    section: ServerSettings
    name: Max Tamed Dinos Soft Tame Limit
    help: Soft server-wide tame limit (used with DestroyTamesOverTheSoftTameLimit).
    type: int
    default: 5000
  - key: MaxTamedDinos_SoftTameLimit_CountdownForDeletionDuration
    section: ServerSettings
    name: Max Tamed Dinos Soft Tame Limit Countdown For Deletion Duration
    help: Seconds before soft-tamed dinos are auto-destroyed.
    type: int
    default: 604800
  - key: MaxTrainCars
    section: ServerSettings
    name: Max Train Cars
    help: Maximum number of carts a train cave can have.
    type: int
    default: 8
  - key: MaxTributeDinos
    section: ServerSettings
    name: Max Tribute Dinos
    help: Slots for uploaded creatures via Tribute (upload slots).
    type: int
    default: 20
  - key: MaxTributeItems
    section: ServerSettings
    name: Max Tribute Items
    help: Slots for uploaded items/resources via Tribute.
    type: int
    default: 50
  - key: NightTimeSpeedScale
    section: ServerSettings
    name: Night Time Speed Scale
    help: Scaling factor for night-time speed relative to day.
    type: float
    default: 1.0
  - key: NonPermanentDiseases
    section: ServerSettings
    name: Non Permanent Diseases
    help: If true, permanent diseases become non-permanent (lost on respawn).
    type: bool
    default: false
  - key: OverrideOfficialDifficulty
    section: ServerSettings
    name: Override Official Difficulty
    help: Float to override default server difficulty (0.0 disables).
    type: float
    default: 0.0
  - key: OverrideStructurePlatformPrevention
    section: ServerSettings
    name: Override Structure Platform Prevention
    help: If true, allows turrets/platform structures on platform saddles.
    type: bool
    default: false
  - key: OxygenSwimSpeedStatMultiplier
    section: ServerSettings
    name: Oxygen Swim Speed Stat Multiplier
    help: Multiplier for swim speed per oxygen stat level.
    type: float
    default: 1.0
  - key: PerPlatformMaxStructuresMultiplier
    section: ServerSettings
    name: Per Platform Max Structures Multiplier
    help: Multiplier increasing max items placeable on saddles/rafts.
    type: float
    default: 1.0
  - key: PlatformSaddleBuildAreaBoundsMultiplier
    section: ServerSettings
    name: Platform Saddle Build Area Bounds Multiplier
    help: Multiplier to allow placing structures further from platform.
    type: float
    default: 1.0
  - key: PlayerCharacterFoodDrainMultiplier
    section: ServerSettings
    name: Player Character Food Drain Multiplier
    help: Player food consumption scaling.
    type: float
    default: 1.0
  - key: PlayerCharacterHealthRecoveryMultiplier
    section: ServerSettings
    name: Player Character Health Recovery Multiplier
    help: Player health recovery scaling.
    type: float
    default: 1.0
  - key: PlayerCharacterStaminaDrainMultiplier
    section: ServerSettings
    name: Player Character Stamina Drain Multiplier
    help: Player stamina consumption scaling.
    type: float
    default: 1.0
  - key: PlayerCharacterWaterDrainMultiplier
    section: ServerSettings
    name: Player Character Water Drain Multiplier
    help: Player water consumption scaling.
    type: float
    default: 1.0
  - key: PlayerDamageMultiplier
    section: ServerSettings
    name: Player Damage Multiplier
    help: Scaling for player damage dealt.
    type: float
    default: 1.0
  - key: PlayerResistanceMultiplier
    section: ServerSettings
    name: Player Resistance Multiplier
    help: Scaling for player resistance to incoming damage.
    type: float
    default: 1.0
  - key: PreventDiseases
    section: ServerSettings
    name: Prevent Diseases
    help: If true, disables diseases (e.g., Swamp Fever).
    type: bool
    default: false
  - key: PreventMateBoost
    section: ServerSettings
    name: Prevent Mate Boost
    help: If true, disables creature mate boosting.
    type: bool
    default: false
  - key: PreventOfflinePvP
    section: ServerSettings
    name: Prevent Offline PvP
    help: If true, enables Offline Raid Prevention (ORP).
    type: bool
    default: false
  - key: PreventOfflinePvPInterval
    section: ServerSettings
    name: Prevent Offline PvP Interval
    help: Seconds to wait before ORP becomes active for tribe/players.
    type: float
    default: 0.0
  - key: PreventSpawnAnimations
    section: ServerSettings
    name: Prevent Spawn Animations
    help: If true, players spawn without wake-up animation.
    type: bool
    default: false
  - key: PreventTribeAlliances
    section: ServerSettings
    name: Prevent Tribe Alliances
    help: If true, prevents tribes from creating alliances.
    type: bool
    default: false
  - key: ProximityChat
    section: ServerSettings
    name: Proximity Chat
    help: If true, chat is visible only to nearby players.
    type: bool
    default: false
  - key: PvEAllowStructuresAtSupplyDrops
    section: ServerSettings
    name: PvE Allow Structures At Supply Drops
    help: If true, allows building near supply drop points in PvE.
    type: bool
    default: false
  - key: PvEDinoDecayPeriodMultiplier
    section: ServerSettings
    name: PvE Dino Decay Period Multiplier
    help: Creature PvE auto-decay time multiplier.
    type: float
    default: 1.0
  - key: PvPDinoDecay
    section: ServerSettings
    name: PvP Dino Decay
    help: If true, enables creature decay in PvP while ORP active.
    type: bool
    default: false
  - key: RaidDinoCharacterFoodDrainMultiplier
    section: ServerSettings
    name: Raid Dino Character Food Drain Multiplier
    help: Affects food drain rate for raid dinos (e.g., Titanosaurus).
    type: float
    default: 1.0
  - key: RandomSupplyCratePoints
    section: ServerSettings
    name: Random Supply Crate Points
    help: If true, supply drops spawn at random locations.
    type: bool
    default: false
  - key: RCONPort
    section: ServerSettings
    name: RCON Port
    help: TCP port for RCON communication.
    type: int
    default: 27020
  - key: RCONServerGameLogBuffer
    section: ServerSettings
    name: RCON Server Game Log Buffer
    help: Number of game-log lines sent over RCON.
    type: float
    default: 600.0
  - key: ResourcesRespawnPeriodMultiplier
    section: ServerSettings
    name: Resources Respawn Period Multiplier
    help: Scaling factor for resource node respawn timing.
    type: float
    default: 1.0
  - key: ServerAdminPassword
    section: ServerSettings
    name: Server Admin Password
    help: Admin password (clients use via console to gain admin access).
  - key: ServerCrosshair
    section: ServerSettings
    name: Server Crosshair
    help: If false, disables the server crosshair.
    type: bool
    default: true
  - key: ServerForceNoHUD
    section: ServerSettings
    name: Server Force No HUD
    help: If true, HUD is always disabled for non-tribe owned NPCs.
    type: bool
    default: false
  - key: ServerHardcore
    section: ServerSettings
    name: Server Hardcore
    help: If true, enables Hardcore mode (players revert to level 1 on death).
    type: bool
    default: false
  - key: ServerPassword
    section: ServerSettings
    name: Server Password
    help: Server password required to join (if specified).
  - key: serverPVE
    section: ServerSettings
    name: Server PVE
    help: If true, enables PvE mode (disables PvP).
    type: bool
    default: false
  - key: ShowFloatingDamageText
    section: ServerSettings
    name: Show Floating Damage Text
    help: If true, enables popup floating damage text.
    type: bool
    default: false
  - key: ShowMapPlayerLocation
    section: ServerSettings
    name: Show Map Player Location
    help: If false, hides players' precise position on their map.
    type: bool
    default: true
  - key: StructurePickupHoldDuration
    section: ServerSettings
    name: Structure Pickup Hold Duration
    help: Quick pick-up hold duration in seconds (0 = instant).
    type: float
    default: 0.5
  - key: StructurePickupTimeAfterPlacement
    section: ServerSettings
    name: Structure Pickup Time After Placement
    help: Seconds after placement quick pick-up becomes available.
    type: float
    default: 30.0
  - key: StructurePreventResourceRadiusMultiplier
    section: ServerSettings
    name: Structure Prevent Resource Radius Multiplier
    help: Multiplier for structure prevention radius for resources.
    type: float
    default: 1.0
  - key: StructureResistanceMultiplier
    section: ServerSettings
    name: Structure Resistance Multiplier
    help: Scaling for structure resistance to incoming damage.
    type: float
    default: 1.0
  - key: TamingSpeedMultiplier
    section: ServerSettings
    name: Taming Speed Multiplier
    help: Scaling for creature taming speed.
    type: float
    default: 1.0
  - key: TheMaxStructuresInRange
    section: ServerSettings
    name: The Max Structures In Range
    help: Max number of structures constructible in the enforced range.
    type: int
    default: 10500
  - key: TribeNameChangeCooldown
    section: ServerSettings
    name: Tribe Name Change Cooldown
    help: Cooldown in minutes between tribe name changes.
    type: float
    default: 15.0
  - key: XPMultiplier
    section: ServerSettings
    name: XP Multiplier
    help: Scaling for experience gained by players, tribes, and tames.
    type: float
    default: 1.0
  - key: YoungIceFoxDeathCooldown
    section: ServerSettings
    name: Young Ice Fox Death Cooldown
    help: Seconds until Veilwyn can reappear after fatal damage.
    type: int
    default: 3600
  - key: CrossARKAllowForeignDinoDownloads
    section: ServerSettings
    name: Cross ARK Allow Foreign Dino Downloads
    help: If true, allows non-native dinos' tribute downloads on some maps.
    type: bool
    default: false
  - key: noTributeDownloads
    section: ServerSettings
    name: No Tribute Downloads
    help: If true, prevents Cross-ARK data downloads.
    type: bool
    default: false
  - key: PreventDownloadDinos
    section: ServerSettings
    name: Prevent Download Dinos
    help: If true, prevents creature downloads via Cross-ARK.
    type: bool
    default: false
  - key: PreventDownloadItems
    section: ServerSettings
    name: Prevent Download Items
    help: If true, prevents item/resource downloads via Cross-ARK.
    type: bool
    default: false
  - key: PreventDownloadSurvivors
    section: ServerSettings
    name: Prevent Download Survivors
    help: If true, prevents survivor downloads via Cross-ARK.
    type: bool
    default: false
  - key: PreventUploadDinos
    section: ServerSettings
    name: Prevent Upload Dinos
    help: If true, prevents creature uploads via Cross-ARK.
    type: bool
    default: false
  - key: PreventUploadItems
    section: ServerSettings
    name: Prevent Upload Items
    help: If true, prevents item uploads via Cross-ARK.
    type: bool
    default: false
  - key: PreventUploadSurvivors
    section: ServerSettings
    name: Prevent Upload Survivors
    help: If true, prevents survivor uploads via Cross-ARK.
    type: bool
    default: false
  - key: BadWordListURL
    section: ServerSettings
    name: Bad Word List URL
    help: |
      URL(s) to a bad-words list for text filtering.
    default: "http://cdn2.arkdedicated.com/asa/badwords.txt"
  - key: BadWordWhiteListURL
    section: ServerSettings
    name: Bad Word White List URL
    help: |
      URL(s) to a good-words list for text filtering.
    default: "http://cdn2.arkdedicated.com/asa/goodwords.txt"
game:
  - key: BabyCuddleGracePeriodMultiplier
    section: /script/shootergame.shootergamemode
    name: "Baby Cuddle Grace Period Multiplier"
    help: "Scales how long after delaying cuddling with the Baby before Imprinting Quality starts to decrease."
    type: float
    default: 1.0
  - key: BabyCuddleIntervalMultiplier
    section: /script/shootergame.shootergamemode
    name: "Baby Cuddle Interval Multiplier"
    help: "Scales how often babies needs attention for imprinting."
    type: float
    default: 1.0
  - key: BabyCuddleLoseImprintQualitySpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Baby Cuddle Lose Imprint Quality Speed Multiplier"
    help: "Scales how fast Imprinting Quality decreases after the grace period if you haven't yet cuddled with the Baby."
    type: float
    default: 1.0
  - key: BabyFoodConsumptionSpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Baby Food Consumption Speed Multiplier"
    help: "Scales the speed that baby tames eat their food."
    type: float
    default: 1.0
  - key: BabyImprintAmountMultiplier
    section: /script/shootergame.shootergamemode
    name: "Baby Imprint Amount Multiplier"
    help: "Scales the percentage each imprint provides."
    type: float
    default: 1.0
  - key: BabyImprintingStatScaleMultiplier
    section: /script/shootergame.shootergamemode
    name: "Baby Imprinting Stat Scale Multiplier"
    help: "Scales how much of an effect on stats the Imprinting Quality has."
    type: float
    default: 1.0
  - key: BabyMatureSpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Baby Mature Speed Multiplier"
    help: "Scales the maturation speed of babies."
    type: float
    default: 1.0
  - key: bAllowFlyerSpeedLeveling
    section: /script/shootergame.shootergamemode
    name: "Allow Flyer Speed Leveling"
    help: "Specifies whether flyer creatures can have their Movement Speed levelled up."
    type: bool
    default: false
  - key: bAllowSpeedLeveling
    section: /script/shootergame.shootergamemode
    name: "Allow Speed Leveling"
    help: "Specifies whether players and non-flyer creatures can have their Movement Speed levelled up."
    type: bool
    default: false
  - key: bAllowUnlimitedRespecs
    section: /script/shootergame.shootergamemode
    name: "Allow Unlimited Respecs"
    help: "If True, allows more than one usage of Mindwipe Tonic without 24 hours cooldown."
    type: bool
    default: false
  - key: bDisableFriendlyFire
    section: /script/shootergame.shootergamemode
    name: "Disable Friendly Fire"
    help: "If True, prevents Friendly-Fire (among tribe mates/tames/structures)."
    type: bool
    default: false
  - key: bDisablePhotoMode
    section: /script/shootergame.shootergamemode
    name: "Disable Photo Mode"
    help: "Defines if photo mode is allowed (False) or not (True)."
    type: bool
    default: false
  - key: bDisableStructurePlacementCollision
    section: /script/shootergame.shootergamemode
    name: "Disable Structure Placement Collision"
    help: "If True, allows for structures to clip into the terrain."
    type: bool
    default: false
  - key: bIgnoreStructuresPreventionVolumes
    section: /script/shootergame.shootergamemode
    name: "Ignore Structures Prevention Volumes"
    help: "If True, enables building areas where normally it's not allowed, such around some maps' Obelisks, in the Aberration Portal and in Mission Volumes areas on Genesis: Part 1."
    type: bool
    default: false
  - key: bPvEDisableFriendlyFire
    section: /script/shootergame.shootergamemode
    name: "PvE Disable Friendly Fire"
    help: "If True, disabled Friendly-Fire (among tribe mates/tames/structures) in PvE servers."
    type: bool
    default: false
  - key: bShowCreativeMode
    section: /script/shootergame.shootergamemode
    name: "Show Creative Mode"
    help: "If True, adds a button to the pause menu to enable/disable creative mode."
    type: bool
    default: false
  - key: bUseDinoLevelUpAnimations
    section: /script/shootergame.shootergamemode
    name: "Use Dino Level Up Animations"
    help: "If False, tame creatures on level-up will not perform the related animation."
    type: bool
    default: true
  - key: bUseSingleplayerSettings
    section: /script/shootergame.shootergamemode
    name: "Use Singleplayer Settings"
    help: "If True, all game settings will be more balanced for an individual player experience."
    type: bool
    default: false
  - key: ConfigAddNPCSpawnEntriesContainer
    section: /script/shootergame.shootergamemode
    name: "Config Add NPC Spawn Entries Container"
    help: "Adds specific creatures in spawn areas."
    type: any
    default: "N/A"
  - key: CraftingSkillBonusMultiplier
    section: /script/shootergame.shootergamemode
    name: "Crafting Skill Bonus Multiplier"
    help: "Scales the bonus received from upgrading the Crafting Skill."
    type: float
    default: 1.0
  - key: CraftXPMultiplier
    section: /script/shootergame.shootergamemode
    name: "Craft XP Multiplier"
    help: "Scales the amount of XP earned for crafting."
    type: float
    default: 1.0
  - key: CropDecaySpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Crop Decay Speed Multiplier"
    help: "Scales the speed of crop decay in plots."
    type: float
    default: 1.0
  - key: CropGrowthSpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Crop Growth Speed Multiplier"
    help: "Scales the speed of crop growth in plots."
    type: float
    default: 1.0
  - key: CustomRecipeEffectivenessMultiplier
    section: /script/shootergame.shootergamemode
    name: "Custom Recipe Effectiveness Multiplier"
    help: "Scales the effectiveness of custom recipes."
    type: float
    default: 1.0
  - key: CustomRecipeSkillMultiplier
    section: /script/shootergame.shootergamemode
    name: "Custom Recipe Skill Multiplier"
    help: "Scales the effect of the players crafting speed level that is used as a base for the formula in creating a custom recipe."
    type: float
    default: 1.0
  - key: DestroyTamesOverLevelClamp
    section: /script/shootergame.shootergamemode
    name: "Destroy Tames Over Level Clamp"
    help: "Tames that exceed that level will be deleted on server start."
    type: int
    default: 0
  - key: EggHatchSpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Egg Hatch Speed Multiplier"
    help: "Scales the time needed for a fertilised egg to hatch."
    type: float
    default: 1.0
  - key: ExcludeItemIndices
    section: /script/shootergame.shootergamemode
    name: "Exclude Item Indices"
    help: "Excludes an item from supply crates specifying its Item ID."
    type: int
  - key: LimitGeneratorsNum
    section: /script/shootergame.shootergamemode
    name: "Limit Generators Num"
    help: "Limits the number of generators in the area defined by LimitGeneratorsRange."
    type: int
    default: 3
  - key: LimitGeneratorsRange
    section: /script/shootergame.shootergamemode
    name: "Limit Generators Range"
    help: "Sets the area range (in Unreal Units) in which the option LimitGeneratorsNum applies."
    type: int
    default: 15000
  - key: GenericXPMultiplier
    section: /script/shootergame.shootergamemode
    name: "Generic XP Multiplier"
    help: "Scales the amount of XP earned for generic XP (automatic over time)."
    type: float
    default: 1.0
  - key: GlobalItemDecompositionTimeMultiplier
    section: /script/shootergame.shootergamemode
    name: "Global Item Decomposition Time Multiplier"
    help: "Scales the decomposition time of dropped items, loot bags etc."
    type: float
    default: 1.0
  - key: GlobalSpoilingTimeMultiplier
    section: /script/shootergame.shootergamemode
    name: "Global Spoiling Time Multiplier"
    help: "Scales the spoiling time of perishables globally."
    type: float
    default: 1.0
  - key: HairGrowthSpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Hair Growth Speed Multiplier"
    help: "Scales the hair growth."
    type: float
    default: "1.0 (ASE), 0 (ASA)"
  - key: HarvestResourceItemAmountClassMultipliers
    section: /script/shootergame.shootergamemode
    name: "Harvest Resource Item Amount Class Multipliers"
    help: "Scales on a per-resource type basis, the amount of resources harvested."
    type: any
    default: "N/A"
  - key: HarvestXPMultiplier
    section: /script/shootergame.shootergamemode
    name: "Harvest XP Multiplier"
    help: "Scales the amount of XP earned for harvesting."
    type: float
    default: 1.0
  - key: KillXPMultiplier
    section: /script/shootergame.shootergamemode
    name: "Kill XP Multiplier"
    help: "Scale the amount of XP earned for a kill."
    type: float
    default: 1.0
  - key: LayEggIntervalMultiplier
    section: /script/shootergame.shootergamemode
    name: "Lay Egg Interval Multiplier"
    help: "Scales the time between eggs are spawning / being laid."
    type: float
    default: 1.0
  - key: MatingIntervalMultiplier
    section: /script/shootergame.shootergamemode
    name: "Mating Interval Multiplier"
    help: "Scales the interval between tames can mate."
    type: float
    default: 1.0
  - key: MatingSpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Mating Speed Multiplier"
    help: "Scales the speed at which tames mate with each other."
    type: float
    default: 1.0
  - key: MaxFallSpeedMultiplier
    section: /script/shootergame.shootergamemode
    name: "Max Fall Speed Multiplier"
    help: "Defines the falling speed multiplier at which players starts taking fall damage."
    type: float
    default: 1.0
  - key: OverrideNamedEngramEntries
    section: /script/shootergame.shootergamemode
    name: "Override Named Engram Entries"
    help: "Configures the status and requirements for learning an engram, specified by its name."
    type: any
    default: "N/A"
  - key: PerLevelStatsMultiplier_Player[<integer>]
    section: /script/shootergame.shootergamemode
    name: "Per Level Stats Multiplier Player[<integer>]"
    help: "Scales Player stats."
    type: float
  - key: PhotoModeRangeLimit
    section: /script/shootergame.shootergamemode
    name: "Photo Mode Range Limit"
    help: "Defines the maximum distance between photo mode camera position and player position."
    type: int
    default: 3000
  - key: PoopIntervalMultiplier
    section: /script/shootergame.shootergamemode
    name: "Poop Interval Multiplier"
    help: "Scales how frequently survivors can poop."
    type: float
    default: 1.0
  - key: ResourceNoReplenishRadiusPlayers
    section: /script/shootergame.shootergamemode
    name: "Resource No Replenish Radius Players"
    help: "Controls how resources regrow closer or farther away from players."
    type: float
    default: 1.0
  - key: ResourceNoReplenishRadiusStructures
    section: /script/shootergame.shootergamemode
    name: "Resource No Replenish Radius Structures"
    help: "Controls how resources regrow closer or farther away from structures Values higher than 1.0 increase the distance around structures where resources are not allowed to grow back."
    type: float
    default: 1.0
  - key: SpecialXPMultiplier
    section: /script/shootergame.shootergamemode
    name: "Special XP Multiplier"
    help: "Scale the amount of XP earned for SpecialEvent."
    type: float
    default: 1.0
  - key: ValgueroMemorialEntries
    section: /script/shootergame.shootergamemode
    name: "Valguero Memorial Entries"
    help: "The Valguero Memorial is now interactable, honouring those who have ascended by displaying their names."
    type: list
    default: "N/A"
  - key: BaseHexagonRewardMultiplier
    section: /script/shootergame.shootergamemode
    name: "Base Hexagon Reward Multiplier"
    help: "Scales the missions score hexagon rewards."
    type: float
    default: 1.0
  - key: HexagonCostMultiplier
    section: /script/shootergame.shootergamemode
    name: "Hexagon Cost Multiplier"
    help: "Scales the hexagon cost of items in the Hexagon store."
    type: float
    default: 1.0
EOF

	# If a pyenv is required:
	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install pyyaml
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install rcon

	# Use the management utility to store some preferences from the installer
	# Save the preferences for the manager
    if [ "$JOINEDSESSIONNAME" == "1" ]; then
    	"$GAME_DIR/manage.py" --set-config "Joined Session Name" True
    else
    	"$GAME_DIR/manage.py" --set-config "Joined Session Name" False
    fi
}

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
	if download "$GITHUB_SOURCE" "$TARGET"; then
		echo "Downloaded new installer version $GITHUB_VERSION from github.com/${REPO}"
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
					SRC="https://raw.githubusercontent.com/${REPO}/refs/tags/${GITHUB_VERSION}/dist/server-install-debian12.sh"
					if download "$SRC" "$0"; then
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
	INSTALLTYPE="new"
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
	if [ $NONINTERACTIVE -eq 1 ]; then
		echo "Non-interactive uninstall selected, proceeding without confirmation"
	else
		echo "WARNING - You have chosen to uninstall ARK Survival Ascended Dedicated Server"
		echo "This process will remove ALL game data, including player data, maps, and binaries."
		echo "This action is IRREVERSIBLE."
		echo ''

		if prompt_yn -q --invert --default-no "? This will remove all game binary content"; then
			exit
		fi

		if prompt_yn -q --invert --default-no "? This will remove all player and map data"; then
			exit
		fi

		if prompt_yn -q --invert --default-no "? This will remove all service registration files"; then
			exit
		fi
	fi


	if [ -e "$GAME_DIR/manage.py" ]; then
		if prompt_yn -q --default-yes "? Would you like to perform a backup before everything is wiped?"; then
			$GAME_DIR/manage.py --backup
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
	[ -e "$GAME_DIR/.settings.ini" ] && rm "$GAME_DIR/.settings.ini"
	[ -e "$GAME_DIR/configs.yaml" ] && rm "$GAME_DIR/configs.yaml"

	if [ -n "$WARLOCK_GUID" ]; then
		echo "Removing Warlock registration"
		[ -e "/var/lib/warlock/$WARLOCK_GUID.app" ] && rm "/var/lib/warlock/$WARLOCK_GUID.app"
	fi

	exit
fi


############################################
## User Prompts (pre setup)
############################################

# Ask the user some information before installing.
if [ "$INSTALLTYPE" == "new" ]; then
	COMMUNITYNAME="$(prompt_text --default="My Awesome ARK Server" "? What is the community name of the server?")"
elif [ -e "$GAME_DIR/services/ark-island.conf" ]; then
	# To support custom maps, load the existing community name from the island map service file.
	COMMUNITYNAME="$(egrep '^ExecStart' "$GAME_DIR/services/ark-island.conf" | sed 's:.*SessionName="\([^"]*\) (.*:\1:')"
else
	COMMUNITYNAME="My Awesome ARK Server"
fi

if [ "$INSTALLTYPE" == "new" ]; then
	JOINEDSESSIONNAME=$(prompt_yn --default-yes "? Include map names in instance name? e.g. My Awesome ARK Server (Island)")
elif [ -e "$GAME_DIR/.settings.ini" ] && grep -q "joinedsessionname = False" "$GAME_DIR/.settings.ini" ; then
	# Explicitly disabled
	JOINEDSESSIONNAME=0
else
	# Enabled by default
	JOINEDSESSIONNAME=1
fi

# Support legacy vs newsave formats
# https://ark.wiki.gg/wiki/2023_official_server_save_files
# Legacy formats use individual files for each character whereas
# "new" formats save all characters along with the map.
echo ''
if [ -e "$GAME_DIR/services/ark-island.conf" ]; then
	if grep -q '-newsaveformat' "$GAME_DIR/services/ark-island.conf"; then
		echo "Using new save format for existing installation"
		NEWFORMAT=1
	else
		echo "Using legacy save format for existing installation"
		NEWFORMAT=0
	fi
elif [ $OPT_NEWFORMAT -eq 1 ]; then
	echo "Using new save format for existing installation based on explicit argument"
	NEWFORMAT=1
elif [ "$INSTALLTYPE" == "new" ]; then
  	echo "Nitrado and official servers are using a new save format"
  	echo "which combines all player data into the map save files."
  	echo ""
  	echo "If you plan on migrating existing content from those servers,"
  	echo "it is highly recommended to use the new save format."

  	NEWFORMAT=$(prompt_yn --default-no "? Use new save format?")
else
	echo "Using legacy save format for existing installation"
	NEWFORMAT=0
fi

# Load or generate a cluster ID as users usually want to cluster their maps together
if [ -e "$GAME_DIR/services/ark-island.conf" ] && grep -q 'clusterid=' "$GAME_DIR/services/ark-island.conf"; then
	CLUSTERID="grep -Eo 'clusterid=[^ ]*' "$GAME_DIR/services/ark-island.conf" | sed 's:.*=::'"
else
	CLUSTERID="$(random_password 12)"
fi


echo ''
if [ "$WHITELIST" -eq 1 ]; then
	WHITELIST=$(prompt_yn --invert --default-no "? DISABLE whitelist for players?")
else
	WHITELIST=$(prompt_yn --default-no "? Enable whitelist for players?")
fi

echo ''
echo 'Multi-server support is provided via NFS by default,'
echo 'but other file synchronization are possible if you prefer a custom solution.'
echo ''
echo 'This ONLY affects the default NFS, (do not enable if you are using a custom solution like VirtIO-FS or Gluster).'
if [ "$MULTISERVER" -eq 1 ]; then
	MULTISERVER=$(prompt_yn --invert --default-no "? DISABLE multi-server NFS cluster support? (Maps spread across different servers)")

	if [ "$MULTISERVER" -eq 1 ] && [ "$ISPRIMARY" -eq 1 ]; then
		echo ''
		SECONDARYIPS="$(prompt_text --default="" "? Add more secondary IPs to the cluster? (Separate different IPs with spaces, enter to just skip)")"
	fi
else
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
fi

if [ "$INSTALLTYPE" == "new" ]; then
	if [ $OPT_SKIP_FIREWALL -eq 1 ]; then
		FIREWALL=0
	else
		echo ''
		FIREWALL=$(prompt_yn --default-yes "? Enable system firewall (UFW by default)?")
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
	CUSTOM_MAP_ID="$(prompt_text --default="$CUSTOM_MAP_ID" "? Mod/Project ID: ")"

	if [ -z "$CUSTOM_MAP_ID" ]; then
		echo "No Mod ID specified, cannot continue with custom map installation."
		exit 1
	fi

	echo ''
	echo "Please enter the Map Name to install."
	echo "This is usually listed on the Curseforge description page."
	CUSTOM_MAP_NAME="$(prompt_text --default="$CUSTOM_MAP_NAME" "? Mod Name: ")"

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

# Append the cluster ID
GAMEFLAGS="$GAMEFLAGS -clusterid=$CLUSTERID"

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

[Service]
Type=simple
LimitNOFILE=10000
User=$GAME_USER
Group=$GAME_USER
WorkingDirectory=$GAME_DIR/AppFiles/ShooterGame/Binaries/Win64
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
Environment="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_DIR"
Environment="STEAM_COMPAT_DATA_PATH=$GAME_DIR/prefixes/$MAP"
ExecStop=$GAME_DIR/manage.py --pre-stop --service=${MAP}
ExecStartPost=$GAME_DIR/manage.py --post-start --service=${MAP}
TimeoutSec=600s
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
# After modifying, please remember to run \`sudo systemctl daemon-reload\` to apply changes to the system.
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

# The update helper is no longer used as of v2025.12.04
[ -e /etc/systemd/system/ark-updater.service ] && rm /etc/systemd/system/ark-updater.service

if [ -e "$GAME_DIR/update.sh" ]; then
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
fi

systemctl daemon-reload


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
install_management

# As of v2025.11.27 these scripts have been ported to the management console.
if [ -e "$GAME_DIR/backup.sh" ]; then
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
fi

# As of v2025.11.27 these scripts have been ported to the management console.
if [ -e "$GAME_DIR/restore.sh" ]; then
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
fi


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

# Register with Warlock
if [ -n "$WARLOCK_GUID" ]; then
	echo -n "$GAME_DIR" > "/var/lib/warlock/$WARLOCK_GUID.app"
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
