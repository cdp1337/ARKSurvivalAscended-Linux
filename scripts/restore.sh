#!/bin/bash
#
# Restore all player data from a backup file
#
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# compile:noescape
GAME_MAPS="$GAME_MAPS"
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
SAVE_DIR="$GAME_DIR/AppFiles/ShooterGame/Saved"
# compile:escape

if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root or with sudo!" >&2
	exit 1
fi

# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		echo "WARNING - $MAP is still running"
		echo "Restore cannot proceed with a map actively running."
		exit 1
	fi
done

if [ -z "$1" ]; then
	echo "ERROR - no source file specified"
	echo "Usage: $0 <source.tgz>"
	exit 1
fi

if [ ! -e "$1" ]; then
	echo "ERROR - cannot read source $1"
	echo "Usage: $0 <source.tgz>"
	exit 1
fi

echo "Extracting $1"
tar -xzf "$1" -C $SAVE_DIR
if [ $? -ne 0 ]; then
	echo "ERROR - failed to extract $1"
	exit 1
fi

if [ -e $SAVE_DIR/.services ]; then
	echo "Restoring service files"
	chown -R root:root $SAVE_DIR/.services
	cp $SAVE_DIR/.services/* /etc/systemd/system/ -r
	systemctl daemon-reload
	rm -fr "$SAVE_DIR/.services"
fi

echo "Ensuring permissions"
chown -R $GAME_USER:$GAME_USER $SAVE_DIR
