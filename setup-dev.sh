#!/bin/bash
#
# Setup this project for development

HERE="$(dirname "$(realpath "$0")")"
# Pull the requested version of the manager from the installation script
WARLOCK_MANAGER="$(grep 'install_warlock_manager' "$HERE/src/server-install-debian12.sh" | grep -v '#' | head -n1 | cut -d ' ' -f 4 | sed 's:"::g' | sed "s:'::g")"
WARLOCK_MANAGER="${WARLOCK_MANAGER:-main}"
WARLOCK_NOTICE=0

if [[ "$WARLOCK_MANAGER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	# Full version string specified; the release branch probably contains the newest version.
	WARLOCK_MANAGER="release-v$(echo $WARLOCK_MANAGER | sed 's:\.[0-9]*$::')"
	WARLOCK_NOTICE=1
elif [[ "$WARLOCK_MANAGER" =~ ^[0-9]+\.[0-9]+$ ]]; then
	# If a release version is requested, switch to the development branch related to that branch.
	# This could cause a potential disconnect between dev and production versions,
	# but it allows for testing development of a specific branch prior to deployment.
	WARLOCK_MANAGER="release-v${WARLOCK_MANAGER}"
	WARLOCK_NOTICE=1
fi

# Setup a virtual environment for Python with the necessary dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install --force-reinstall warlock-manager@git+https://github.com/BitsNBytes25/Warlock-Manager.git@${WARLOCK_MANAGER}

# Install newest version of scripts compiler
if which curl; then
	curl -sL https://raw.githubusercontent.com/eVAL-Agency/ScriptsCollection/refs/heads/main/compile.py -o compile.py
elif which wget; then
	wget https://raw.githubusercontent.com/eVAL-Agency/ScriptsCollection/refs/heads/main/compile.py -O compile.py
else
	echo "Neither curl nor wget is installed. Please install one of them to download the scripts compiler."
	exit 1
fi
chmod +x compile.py

# Ensure compile.sources will install the bootstrap files from the appropriate branch.
if [ -e "$HERE/compile.sources" ]; then
	if grep -q "warlock=github:BitsNBytes25/Warlock-Manager" "$HERE/compile.sources"; then
		# Update the existing line for warlock-manager if it exists
		sed -i "s|warlock=github:BitsNBytes25/Warlock-Manager:.*|warlock=github:BitsNBytes25/Warlock-Manager:${WARLOCK_MANAGER}|g" "$HERE/compile.sources"
	else
		# Append the line for warlock-manager if it doesn't exist
		echo "warlock=github:BitsNBytes25/Warlock-Manager:${WARLOCK_MANAGER}" >> "$HERE/compile.sources"
	fi
else
	cat > "$HERE/compile.sources" <<EOF
warlock=github:BitsNBytes25/Warlock-Manager:${WARLOCK_MANAGER}
EOF
fi

if [ "$WARLOCK_NOTICE" -eq 1 ]; then
	echo "NOTICE - using ${WARLOCK_MANAGER} branch for local checkout which may differ from PyPI package!"
	echo "         This development branch may contain fixes not present in the release."
fi
