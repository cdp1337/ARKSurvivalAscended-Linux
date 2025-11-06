#!/bin/bash
#
# Update ARK Survival Ascended Dedicated Server
#
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# List of all maps available on this platform
# compile:noescape
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


	if [ $? -ne 0 ]; then
		echo "Game update failed!" >&2
		exit 1
	fi
}

if $GAME_DIR/manage.py --is-running; then
	echo "Game server is running, not updating"
	exit 0
fi

update_game