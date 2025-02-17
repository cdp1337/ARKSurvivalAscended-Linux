#!/bin/bash
#
# Update ARK Survival Ascended Dedicated Server
#
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# List of all maps available on this platform
# compile:noescape
GAME_MAPS="$GAME_MAPS"
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
STEAM_ID="$STEAM_ID"
# compile:escape

# This script is expected to be run as the steam user, (as that is the owner of the game files).
# If another user calls this script, sudo will be used to switch to the steam user.
if [ "$(whoami)" == "$GAME_USER" ]; then
	SUDO_NEEDED=0
else
	SUDO_NEEDED=1
fi

function update_game {
	echo "Running game update"
	if [ "$SUDO_NEEDED" -eq 1 ]; then
		sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update $STEAM_ID validate +quit
	else
		/usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update $STEAM_ID validate +quit
	fi

	if [ $? -ne 0 ]; then
		echo "Game update failed!" >&2
		exit 1
	fi
}

# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		echo "WARNING - $MAP is still running"
		RUNNING=1
	fi
done

if [ $RUNNING -eq 1 ]; then
	echo "At least one map is still running, do you still want to run updates? (y/N): "
	read UP
	if [ "$UP" == "y" -o "$UP" == "Y" ]; then
		RUNNING=0
	fi
fi

if [ $RUNNING -eq 0 ]; then
	update_game
else
	echo "Game server is already running, not updating"
fi
