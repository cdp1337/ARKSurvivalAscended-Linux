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
#   --dir=<string> - Use a custom installation directory instead of the default OPTIONAL
#   --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
#   --skip-firewall  - Skip installing/configuring the firewall
#   --new-format  - Use the new save format (Nitrado/Official server compatible) OPTIONAL
#   --branch=<str> - Use a specific branch of the management script repository DEFAULT=main
#
# Changelog:
#   20260426 - Complete rewrite of the system for API 2.2
#            - Individual map backup/restore
#            - Better port conflict detection
#            - New TUI
#            - Mod support
#            - Custom map support
#            - Upgrade Proton to 10.34
#            - Add support for ASA API
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

function usage() {
  cat >&2 <<EOD
Usage: $0 [options]

Options:
    --reset-proton  - Reset proton directories back to default
    --force-reinstall  - Force a reinstall of the game binaries, mods, and engine
    --uninstall  - Uninstall the game server
    --dir=<string> - Use a custom installation directory instead of the default OPTIONAL
    --non-interactive  - Run the installer in non-interactive mode (useful for scripted installs)
    --skip-firewall  - Skip installing/configuring the firewall
    --new-format  - Use the new save format (Nitrado/Official server compatible) OPTIONAL
    --branch=<str> - Use a specific branch of the management script repository DEFAULT=main

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
OPT_OVERRIDE_DIR=""
NONINTERACTIVE=0
SKIP_FIREWALL=0
OPT_NEWFORMAT=0
BRANCH="main"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--reset-proton) OPT_RESET_PROTON=1;;
		--force-reinstall) OPT_FORCE_REINSTALL=1;;
		--uninstall) OPT_UNINSTALL=1;;
		--dir=*|--dir)
			[ "$1" == "--dir" ] && shift 1 && OPT_OVERRIDE_DIR="$1" || OPT_OVERRIDE_DIR="${1#*=}"
			[ "${OPT_OVERRIDE_DIR:0:1}" == "'" ] && [ "${OPT_OVERRIDE_DIR:0-1}" == "'" ] && OPT_OVERRIDE_DIR="${OPT_OVERRIDE_DIR:1:-1}"
			[ "${OPT_OVERRIDE_DIR:0:1}" == '"' ] && [ "${OPT_OVERRIDE_DIR:0-1}" == '"' ] && OPT_OVERRIDE_DIR="${OPT_OVERRIDE_DIR:1:-1}"
			;;
		--non-interactive) NONINTERACTIVE=1;;
		--skip-firewall) SKIP_FIREWALL=1;;
		--new-format) OPT_NEWFORMAT=1;;
		--branch=*|--branch)
			[ "$1" == "--branch" ] && shift 1 && BRANCH="$1" || BRANCH="${1#*=}"
			[ "${BRANCH:0:1}" == "'" ] && [ "${BRANCH:0-1}" == "'" ] && BRANCH="${BRANCH:1:-1}"
			[ "${BRANCH:0:1}" == '"' ] && [ "${BRANCH:0-1}" == '"' ] && BRANCH="${BRANCH:1:-1}"
			;;
		-h|--help) usage;;
		*) echo "Unknown argument: $1" >&2; usage;;
	esac
	shift 1
done

##
# Simple check to enforce the script to be run as root
if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi
##
# Simple wrapper to emulate `which -s`
#
# The -s flag is not available on all systems, so this function
# provides a consistent way to check for command existence
# without having to include '&>/dev/null' everywhere.
#
# Returns 0 on success, 1 on failure
#
# Arguments:
#   $1 - Command to check
#
# CHANGELOG:
#   2025.12.15 - Initial version (for a regression fix)
#
function cmd_exists() {
	local CMD="$1"
	which "$CMD" &>/dev/null
	return $?
}

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
# Arguments:
#   --no-overwrite       Skip download if destination file already exists
#
# CHANGELOG:
#   2026.04.21 - Add retry in curl to retry on connection issues, (looking at you Github)
#   2025.12.15 - Use cmd_exists to fix regression bug
#   2025.12.04 - Add --no-overwrite option to allow skipping download if the destination file exists
#   2025.11.23 - Download to a temp location to verify download was successful
#              - use which -s for cleaner checks
#   2025.11.09 - Initial version
#
function download() {
	# Argument parsing
	local SOURCE="$1"
	local DESTINATION="$2"
	local OVERWRITE=1
	local TMP=$(mktemp)
	shift 2

	while [ $# -ge 1 ]; do
    		case $1 in
    			--no-overwrite)
    				OVERWRITE=0
    				;;
    		esac
    		shift
    	done

	if [ -z "$SOURCE" ] || [ -z "$DESTINATION" ]; then
		echo "download: Missing required parameters!" >&2
		return 1
	fi

	if [ -f "$DESTINATION" ] && [ $OVERWRITE -eq 0 ]; then
		echo "download: Destination file $DESTINATION already exists, skipping download." >&2
		return 0
	fi

	if cmd_exists curl; then
		if curl --connect-timeout 10 --retry 3 --retry-delay 10 -fsL "$SOURCE" -o "$TMP"; then
			mv $TMP "$DESTINATION"
			return 0
		else
			echo "download: curl failed to download $SOURCE" >&2
			return 1
		fi
	elif cmd_exists wget; then
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
# Check if the OS is "like" a certain type
#
# Returns 0 if true, 1 if false
#
# Usage:
#   if os_like debian; then ... ; fi
#
function os_like() {
	local OS="$1"

	if [ -f '/etc/os-release' ]; then
		ID="$(egrep '^ID=' /etc/os-release | sed 's:ID=::')"
		LIKE="$(egrep '^ID_LIKE=' /etc/os-release | sed 's:ID_LIKE=::')"

		if [[ "$LIKE" =~ "$OS" ]] || [ "$ID" == "$OS" ]; then
			return 0;
		fi
	fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_debian)" -eq 1 ]; then ... ; fi
#   if os_like_debian -q; then ... ; fi
#
function os_like_debian() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like debian || os_like ubuntu; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_ubuntu)" -eq 1 ]; then ... ; fi
#   if os_like_ubuntu -q; then ... ; fi
#
function os_like_ubuntu() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like ubuntu; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_rhel)" -eq 1 ]; then ... ; fi
#   if os_like_rhel -q; then ... ; fi
#
function os_like_rhel() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like rhel || os_like fedora || os_like rocky || os_like centos; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_suse)" -eq 1 ]; then ... ; fi
#   if os_like_suse -q; then ... ; fi
#
function os_like_suse() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like suse; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_arch)" -eq 1 ]; then ... ; fi
#   if os_like_arch -q; then ... ; fi
#
function os_like_arch() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if os_like arch; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	fi

	if [ $QUIET -eq 0 ]; then echo 0; fi
	return 1
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_bsd)" -eq 1 ]; then ... ; fi
#   if os_like_bsd -q; then ... ; fi
#
function os_like_bsd() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if [ "$(uname -s)" == 'FreeBSD' ]; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	else
		if [ $QUIET -eq 0 ]; then echo 0; fi
		return 1
	fi
}

##
# Check if the OS is "like" a certain type
#
# ie: "ubuntu" will be like "debian"
#
# Returns 0 if true, 1 if false
# Prints 1 if true, 0 if false
#
# Usage:
#   if [ "$(os_like_macos)" -eq 1 ]; then ... ; fi
#   if os_like_macos -q; then ... ; fi
#
function os_like_macos() {
	local QUIET=0
	while [ $# -ge 1 ]; do
		case $1 in
			-q)
				QUIET=1;;
		esac
		shift
	done

	if [ "$(uname -s)" == 'Darwin' ]; then
		if [ $QUIET -eq 0 ]; then echo 1; fi
		return 0;
	else
		if [ $QUIET -eq 0 ]; then echo 0; fi
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
#   2026.04.26 - Supress command output on Ubuntu
#   2026.04.23 - Register proton path in alternatives to /usr/local/bin/proton
#   2025.11.23 - Use download scriptlet for downloading
#   2024.12.22 - Initial version
#
function install_proton() {
	VERSION="${1:-9-21}"

	PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${VERSION}/GE-Proton${VERSION}.tar.gz"
	PROTON_TGZ="$(basename "$PROTON_URL")"
	PROTON_NAME="$(basename "$PROTON_TGZ" ".tar.gz")"

	# We will use this directory as a working directory for source files that need downloaded.
	[ -d /opt/script-collection ] || mkdir -p /opt/script-collection

	# Grab Proton from Glorious Eggroll
	if ! download "$PROTON_URL" "/opt/script-collection/$PROTON_TGZ" --no-overwrite; then
		echo "install_proton: Cannot download Proton from ${PROTON_URL}!" >&2
		return 1
	fi

	# Extract GE Proton into /opt
	if [ ! -e "/opt/script-collection/$PROTON_NAME" ]; then
		tar -x -C /opt/script-collection/ -f "/opt/script-collection/$PROTON_TGZ"
	fi

	# Update distro registrations for alternative software.
	if os_like debian; then
		update-alternatives --install "/usr/local/bin/proton" "proton" "/opt/script-collection/$PROTON_NAME/proton" 1 >&2
	elif os_like rhel; then
		alternatives --install "/usr/local/bin/proton" "proton" "/opt/script-collection/$PROTON_NAME/proton" 1 >&2
	elif os_like suse; then
		update-alternatives --install "/usr/local/bin/proton" "proton" "/opt/script-collection/$PROTON_NAME/proton" 1 >&2
	fi

	echo "/opt/script-collection/$PROTON_NAME"
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
#   2025.12.15 - Use cmd_exists to fix regression bug
#   2025.04.10 - Switch from "systemctl list-unit-files" to "which" to support older systems
function get_available_firewall() {
	if cmd_exists firewall-cmd; then
		echo "firewalld"
	elif cmd_exists ufw; then
		echo "ufw"
	elif systemctl list-unit-files iptables.service &>/dev/null; then
		echo "iptables"
	else
		echo "none"
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
#
# CHANGELOG:
#
#   2025.12.16 - Ensure steam GPG key is readable by apt
#   2025.11.09 - Switch to using download to support curl/wget abstraction
#   2025.11.03 - Add support for Debian 13
#   2024.12.23 - Add support for non-interactive acceptance of Steam license
#   2024.12.22 - Initial version
#
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
		chmod +r /usr/share/keyrings/steam.gpg
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
#   2026.01.09 - Cleanup os_like a bit and add support for RHEL 9's dnf
#   2025.04.10 - Set Debian frontend to noninteractive
#
function package_install (){
	echo "package_install: Installing $*..."

	if os_like_bsd -q; then
		pkg install -y $*
	elif os_like_debian -q; then
		DEBIAN_FRONTEND="noninteractive" apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install -y $*
	elif os_like_rhel -q; then
		if [ "$(os_version)" -ge 9 ]; then
			dnf install -y $*
		else
			yum install -y $*
		fi
	elif os_like_arch -q; then
		pacman -Syu --noconfirm $*
	elif os_like_suse -q; then
		zypper install -y $*
	else
		echo 'package_install: Unsupported or unknown OS' >&2
		echo 'Please report this at https://github.com/eVAL-Agency/ScriptsCollection/issues' >&2
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
# Install firewalld
#
# CHANGELOG:
#   2026.03.16 - Switch awk to use $NF for better support
#
function install_firewalld() {
	package_install firewalld

	# Auto-add the current user's remote IP to the whitelist (anti-lockout rule)
	local TTY_IP="$(who am i | awk '{print $NF}' | sed 's/[()]//g')"
	if [ -n "$TTY_IP" ]; then
		# Anti-lockout rule based on first install of firewalld
		firewall-cmd --zone=trusted --add-source=$TTY_IP --permanent
	fi
}

##
# Install the system default firewall based on the OS type
#
# For Debian/Ubuntu, this installs UFW
# For RHEL/CentOS, this installs firewalld
# For SUSE, this installs firewalld
# For other OS types, this defaults to installing UFW
#
function firewall_install() {
	local FIREWALL

	FIREWALL=$(get_available_firewall)
	if [ "$FIREWALL" != "none" ]; then
		return
	fi

	if os_like_debian -q; then
		install_ufw
	elif os_like_rhel -q; then
		install_firewalld
	elif os_like_suse -q; then
		install_firewalld
	else
		install_ufw
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
# Checks NONINTERACTIVE, CI, DEBIAN_FRONTEND, and TERM.
#
# Returns 0 (true) if non-interactive, 1 (false) if interactive.
#
# CHANGELOG:
#   2025.12.16 - Remove TTY checks to avoid false positives in some environments
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

	# dumb terminal
	if [ "${TERM:-}" = "dumb" ]; then
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
#   2025.12.16 - Add text output for non-interactive and empty responses
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
		DEFAULT_TEXT="yes"
		DEFAULT="$YES"
		DEFAULT_CODE=$TRUE
		echo -n "> (Y/n): " >&2
	else
		DEFAULT_TEXT="no"
		DEFAULT="$NO"
		DEFAULT_CODE=$FALSE
		echo -n "> (y/N): " >&2
	fi

	if is_noninteractive; then
		# In non-interactive mode, return the default value
		echo "$DEFAULT_TEXT (default non-interactive)" >&2
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
		"")
			echo "$DEFAULT_TEXT (default choice)" >&2
			if [ $QUIET -eq 0 ]; then
				echo $DEFAULT
			fi
			return $DEFAULT_CODE;;
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
#   WARLOCK_GUID - Warlock GUID for this game
#
# @param $1 Application Repo Name (e.g., user/repo)
# @param $2 Application Branch Name (default: main)
# @param $3 Warlock Manager Branch to use (default: release-v2)
#
# CHANGELOG:
#   20260326 - Add support for full version strings
#   20260325 - Update to install warlock-manager from PyPI if a version number is specified instead of a branch name
#   20260319 - Add third option to specify the version of Warlock Manager to use as the base
#   20260301 - Update to install warlock-manager from github (along with its dependencies) as a pip package
#
function install_warlock_manager() {
	print_header "Performing install_management"

	# Install management console and its dependencies

	# Source URL to download the application from
	local SRC=""
	# Github repository of the source application
	local REPO="$1"
	# Branch of the source application to download from (default: main)
	local BRANCH="${2:-main}"
	# Branch of Warlock Manager to install (default: release-v2)
	local MANAGER_BRANCH="${3:-release-v2}"
	local MANAGER_SOURCE
	local MANAGER_SHA

	if [[ "$MANAGER_BRANCH" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		# Support 1.2.3 version strings; indicates at least .3 of the revision.
		MANAGER_SOURCE="pip"
		MANAGER_BRANCH=">=${MANAGER_BRANCH},<=$(echo $MANAGER_BRANCH | sed 's:\.[0-9]*$:.9999:')"
	elif [[ "$MANAGER_BRANCH" =~ ^[0-9]+\.[0-9]+$ ]]; then
		# Support 1.2 version strings; indicates it just must be within this API version
        MANAGER_SOURCE="pip"
        MANAGER_BRANCH=">=${MANAGER_BRANCH}.0,<=${MANAGER_BRANCH}.9999"
    else
    	# Not a version string, probably a branch name instead.
        MANAGER_SOURCE="github"
    fi

	SRC="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/dist/manage.py"

	if ! download "$SRC" "$GAME_DIR/manage.py"; then
		echo "Could not download management script!" >&2
		exit 1
	fi

	chown $GAME_USER:$GAME_USER "$GAME_DIR/manage.py"
	chmod +x "$GAME_DIR/manage.py"

	# Record the hash of the install and branch name for display in the management UI and checking for updates.
	# We use the direct hash because installation scripts may not necessarily use tagged versions.
	MANAGER_SHA="$(curl -s "https://api.github.com/repos/${REPO}/commits/${BRANCH}" \
        | grep '"sha":' \
        | head -n 1 \
        | sed -E 's/.*"sha": *"([^"]+)".*/\1/')"

	# Record this hash along with the branch into a file accessible by the manager.
	# This will be read by the Python, so JSON is fine.
	cat > "$GAME_DIR/.manage.json" <<EOF
{
	"source": "github",
	"repo": "${REPO}",
	"branch": "${BRANCH}",
	"commit": "${MANAGER_SHA}",
	"game": "${WARLOCK_GUID}"
}
EOF
	chown $GAME_USER:$GAME_USER "$GAME_DIR/.manage.json"

	# Install configuration definitions
	cat > "$GAME_DIR/configs.yaml" <<EOF
manager:
  - name: Steam Branch
    section: Steam
    key: steam_branch
    type: str
    default: public
    help: "The Steam branch to install the server from (e.g., stable, experimental)."
    group: Settings
  - name: Steam Branch Password
    section: Steam
    key: steam_branch_password
    type: str
    default: ""
    help: "The password for accessing a private Steam branch, if applicable."
    group: Settings
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
  - name: Instance Started (Discord)
    section: Messages
    key: map_started
    type: str
    default: "{instance} has started! :rocket:"
    help: "Custom message sent to Discord when the server starts, use '{instance}' to insert the map name"
  - name: Instance Stopping (Discord)
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
  - name: Community Name
    key: communityname
    section: Manager
    type: str
    help: Shared community name for instances, has no effect unless "Joined Session Name" is enabled.
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
  - name: Default New Save Format
    key: defaultnewsaveformat
    section: Environment
    type: bool
    default: true
    help: Defaults new maps to use the new save format, a single file for all player data and maps
  - name: Default Cluster ID
    key: defaultclusterid
    section: Cluster
    type: str
    help: "The default cluster ID to use for new servers."
  - name: Default Proton Path
    key: defaultprotonpath
    section: Environment
    type: str
    help: "The default Proton path to use for new servers."
  - name: ASA API Loader
    section: system
    key: asaapiloader
    type: str
    default: "None"
service:
  - name: Map Name
    section: system
    key: system_mapname
    type: str
    group: Basic
    help: System name of the map used for this instance, REQUIRED for this service to work. One of 'TheIsland_WP', 'TheCenter_WP', or any other valid map identifier.
  - key: allowicefox
    section: flag
    name: Allow Veilwyn Transfers
    type: bool
    default: false
    group: Transfers
  - key: CrossARKAllowForeignDinoDownloads
    section: option
    name: Cross ARK Allow Foreign Dino Downloads (Instance)
    help: If true, allows non-native dinos' tribute downloads on some maps.
    type: bool
    default: false
    group: Transfers
  - key: noTributeDownloads
    section: option
    name: No Tribute Downloads (Instance)
    help: If true, prevents Cross-ARK data downloads.
    type: bool
    default: false
    group: Transfers
  - key: PreventDownloadDinos
    section: option
    name: Prevent Download Dinos (Instance)
    help: If true, prevents creature downloads via Cross-ARK.
    type: bool
    default: false
    group: Transfers
  - key: PreventDownloadItems
    section: option
    name: Prevent Download Items (Instance)
    help: If true, prevents item/resource downloads via Cross-ARK.
    type: bool
    default: false
    group: Transfers
  - key: PreventDownloadSurvivors
    section: option
    name: Prevent Download Survivors (Instance)
    help: If true, prevents survivor downloads via Cross-ARK.
    type: bool
    default: false
    group: Transfers
  - key: PreventUploadDinos
    section: option
    name: Prevent Upload Dinos (Instance)
    help: If true, prevents creature uploads via Cross-ARK.
    type: bool
    default: false
    group: Transfers
  - key: PreventUploadItems
    section: option
    name: Prevent Upload Items (Instance)
    help: If true, prevents item uploads via Cross-ARK.
    type: bool
    default: false
    group: Transfers
  - key: PreventUploadSurvivors
    section: option
    name: Prevent Upload Survivors (Instance)
    help: If true, prevents survivor uploads via Cross-ARK.
    type: bool
    default: false
    group: Transfers
  - name: Session Name
    section: option
    key: SessionName
    type: str
    help: "Set the name of the server session as it appears in the server browser."
    group: Basic
  - name: Alt Save Directory
    section: option
    key: AltSaveDirectoryName
    type: str
    help: "Specify an alternative save directory for server data."
    group: Settings
  - name: Always Tick Dedicated Skeletal Meshes
    section: flag
    key: AlwaysTickDedicatedSkeletalMeshes
    type: bool
    help: "Optimize performance by always ticking skeletal meshes on dedicated servers."
    group: Performance
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
    group: Performance
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
    group: Security
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
    group: Performance
  - name: New Save Format
    section: flag
    key: newsaveformat
    type: bool
    help: Enables the new save format for server saves, improving performance and compatibility with future updates.
    group: Settings
  - name: Mods
    section: flag
    key: mods
    type: str
    help: Specifies CurseForge Mod Project IDs. Mods are updated automatically when starting the server.
    group: Mods
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
    group: Mods
  - name: Port
    section: flag
    key: port
    type: int
    default: 7777
    help: "Set the main port for game connections."
    group: Settings
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
    group: Settings
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
    group: Basic
  - name: No Transfer From Filtering
    section: flag
    key: NoTransferFromFiltering
    type: bool
    help: "Prevents ARK Data usage between single player and servers who do not have a cluster ID."
    group: Transfers
  - name: Convert To Store
    section: flag
    key: converttostore
    type: bool
    help: "Converts legacy save files to the store format on server save."
    group: Settings
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
    group: Performance
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
    group: Performance
  - name: Server Platform
    section: flag
    key: ServerPlatform
    type: str
    default: "ALL"
    help: "Allows the server to accept specified platforms. Options are PC for Steam, PS5 for PlayStation 5, XSX for XBOX, WINGDK for Microsoft Store, ALL for crossplay between PC (Steam and Windows Store) and all consoles."
    group: Basic
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
    group: Performance
  - name: Difficulty Offset
    section: option
    key: DifficultyOffset
    type: float
    default: 1.0
    help: "Sets the difficulty offset for the server, affecting wild creature levels."
    group: Difficulty
  - name: RCON Port
    section: option
    key: RCONPort
    type: int
    default: 27020
    help: "Sets the port for RCON (Remote Console) connections."
    group: Settings
  - name: RCON Enabled
    section: option
    key: RCONEnabled
    type: bool
    default: false
    help: "Enables or disables RCON (Remote Console) access to the server."
    group: Settings
  - name: Server Admin Password
    section: option
    key: ServerAdminPassword
    type: str
    help: "Sets the password for server admin access via RCON."
    group: Settings
  - name: Server Hardcore
    section: option
    key: ServerHardcore
    type: bool
    default: false
    help: "Enables hardcore mode on the server, where players have only one life."
    group: Difficulty
  - name: Server Password
    section: option
    key: ServerPassword
    type: str
    help: "Sets a password required for players to join the server."
    group: Security
  - name: Server PVE
    section: option
    key: serverPVE
    type: bool
    default: false
    help: "Enables Player vs Environment mode on the server, disabling player vs player combat."
    group: Difficulty
  - name: XP Multiplier
    section: option
    key: XPMultiplier
    type: float
    default: 1.0
    help: "Sets the experience points multiplier for players on the server."
    group: Difficulty
  - name: Mod Loader
    section: system
    key: modloader
    type: str
    default: "None"
    options:
      - "None"
      - "ASA API Loader"
    group: Mods
  - name: Proton Path
    key: protonpath
    section: system
    group: Settings
    type: str
    help: "The Proton path to use for this instance."
gus:
  - key: LimitBunkersPerTribe
    section: ServerSettings
    name: Limit Bunkers Per Tribe
    help: If true, limits the number of bunkers a tribe can own.
    type: bool
    default: true
  - key: LimitBunkersPerTribeNum
    section: ServerSettings
    name: Limit Bunkers Per Tribe Num
    help: Maximum number of bunkers a tribe can own (if limiting enabled).
    type: int
    default: 3
  - key: AllowBunkersInPreventionZones
    section: ServerSettings
    name: Allow Bunkers In Prevention Zones
    help: If true, allows building bunkers in structure prevention zones.
    type: bool
    default: false
  - key: AllowRidingDinosInsideBunkers
    section: ServerSettings
    name: Allow Riding Dinos Inside Bunkers
    help: If true, allows riding creatures while inside bunkers.
    type: bool
    default: true
  - key: AllowBunkerModulesAboveGround
    section: ServerSettings
    name: Allow Bunker Modules Above Ground
    help: If true, allows placing bunker modules above ground level.
    type: bool
    default: false
  - key: AllowDinoAIInsideBunkers
    section: ServerSettings
    name: Allow Dino AI Inside Bunkers
    help: If true, allows wild creature AI to function inside bunkers.
    type: bool
    default: true
  - key: AllowBunkerModulesInPreventionZones
    section: ServerSettings
    name: Allow Bunker Modules In Prevention Zones
    help: If true, allows placing bunker modules in structure prevention zones.
    type: bool
    default: false
  - key: MinDistanceBetweenBunkers
    section: ServerSettings
    name: Min Distance Between Bunkers
    help: Minimum distance required between two bunkers.
    type: float
    default: 3000.0
  - key: EnemyAccessBunkerHPThreshold
    section: ServerSettings
    name: Enemy Access Bunker HP Threshold
    help: Percentage HP threshold below which enemies can enter bunkers.
    type: float
    default: 0.25
  - key: BunkerUnderHPThresholdDmgMultiplier
    section: ServerSettings
    name: Bunker Under HP Threshold Dmg Multiplier
    help: Damage multiplier applied to bunkers below the HP threshold.
    type: float
    default: 0.05
  - key: CryoHospitalHoursToRegenHP
    section: ServerSettings
    name: Cryo Hospital Hours To Regen HP
    help: Hours required in a cryo hospital to fully regenerate HP.
    type: float
    default: 1.0
  - key: CryoHospitalHoursToRegenFood
    section: ServerSettings
    name: Cryo Hospital Hours To Regen Food
    help: Hours required in a cryo hospital to fully regenerate food.
    type: float
    default: 24.0
  - key: CryoHospitalHoursToDrainTorpor
    section: ServerSettings
    name: Cryo Hospital Hours To Drain Torpor
    help: Hours required in a cryo hospital to fully drain torpor.
    type: float
    default: 1.0
  - key: CryoHospitalMatingCooldownReduction
    section: ServerSettings
    name: Cryo Hospital Mating Cooldown Reduction
    help: Multiplier reducing mating cooldown when in a cryo hospital.
    type: float
    default: 2.0
  - key: BloodforgeReinforceExtraDurability
    section: ServerSettings
    name: Bloodforge Reinforce Extra Durability
    help: Extra durability added when reinforcing items at the Bloodforge.
    type: float
    default: 0.3
  - key: BloodforgeReinforceResourceCostMultiplier
    section: ServerSettings
    name: Bloodforge Reinforce Resource Cost Multiplier
    help: Multiplier for resource costs when reinforcing items at the Bloodforge.
    type: float
    default: 3.0
  - key: BloodforgeReinforceSpeedMultiplier
    section: ServerSettings
    name: Bloodforge Reinforce Speed Multiplier
    help: Multiplier for the speed of reinforcing items at the Bloodforge.
    type: float
    default: 0.1
  - key: MaxActiveOutposts
    section: ServerSettings
    name: Max Active Outposts
    help: Maximum number of active outposts allowed on the server.
    type: int
    default: 1
  - key: MaxActiveResourceCaches
    section: ServerSettings
    name: Max Active Resource Caches
    help: Maximum number of active resource caches allowed on the server.
    type: int
    default: 3
  - key: MaxActiveCityOutposts
    section: ServerSettings
    name: Max Active City Outposts
    help: Maximum number of active city outposts allowed on the server.
    type: int
    default: 1
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
    name: Default Server Admin Password
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
    default: 0.0
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
	chown $GAME_USER:$GAME_USER "$GAME_DIR/configs.yaml"

	# Most games use .settings.ini for manager settings
	touch "$GAME_DIR/.settings.ini"
	chown $GAME_USER:$GAME_USER "$GAME_DIR/.settings.ini"

	# A python virtual environment is now required by Warlock-based managers.
	sudo -u $GAME_USER python3 -m venv "$GAME_DIR/.venv"
	sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install --upgrade pip
	if [ "$MANAGER_SOURCE" == "pip" ]; then
		# Install from PyPI with version specifier
		sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install "warlock-manager${MANAGER_BRANCH}"
	else
		# Install directly from GitHub
		sudo -u $GAME_USER "$GAME_DIR/.venv/bin/pip" install warlock-manager@git+https://github.com/BitsNBytes25/Warlock-Manager.git@$MANAGER_BRANCH
	fi

	# Ensure warlock lib directory exists for supplemental data
	[ -d "/var/lib/warlock" ] || mkdir -p "/var/lib/warlock"
	[ -e /var/lib/warlock/.auth ] || touch /var/lib/warlock/.auth
    # Ensure it's a valid 64-character hash
    if [ "$(cat /var/lib/warlock/.auth | wc -c)" != "64" ]; then
    	cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1 | tr -d '\n' > "/var/lib/warlock/.auth"
    fi
	[ -e "/var/lib/warlock/.email" ] || touch /var/lib/warlock/.email
}


##
# Install Xvfb and (optionally) a daemon helper
#
# Syntax:
#   install_xvfb [--no-daemon] [--display <int>] [--service <name>]
#
# Changelog:
#   20260216 - Initial version
#
function install_xvfb() {
	local SERVICE_DISPLAY=99
	local SERVICE_NAME="xvfb"
	local NO_DAEMON=0

	while [ $# -ge 1 ]; do
		case $1 in
			--no-daemon) NO_DAEMON=1;;
			--display) shift; SERVICE_DISPLAY="$1";;
			--service) shift; SERVICE_NAME="$1";;
		esac
		shift
	done

	package_install xvfb

	if [ "$NO_DAEMON" -eq 0 ]; then
		# Install the daemon helper script
		cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOL
[Unit]
Description=Virtual Frame Buffer (Xvfb)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :${SERVICE_DISPLAY} -screen 0 1024x768x16 -nolisten tcp
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL
		systemctl daemon-reload
		systemctl enable ${SERVICE_NAME}.service
		systemctl start ${SERVICE_NAME}.service

		echo "Xvfb service '${SERVICE_NAME}' installed and started on display :${SERVICE_DISPLAY}."
	fi
}


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
    install_warlock_manager "$REPO" "$BRANCH" 2.2.9

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
