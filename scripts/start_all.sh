#!/bin/bash
#
# Start all ARK server maps that are enabled
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# List of all maps available on this platform
# compile:noescape
GAME_MAPS="$GAME_MAPS"
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
STEAM_ID="$STEAM_ID"
# compile:escape

function start_game {
	echo "Starting game instance $1..."
	sudo systemctl start $1
	echo "Waiting 30 seconds for threads to start"
	for i in {0..9}; do
		sleep 3
		echo -n '.'
	done
	# Check status real quick
	sudo systemctl status $1 | grep Active
}

function update_game {
	echo "Running game update"
	sudo -u $GAME_USER /usr/games/steamcmd +force_install_dir $GAME_DIR/AppFiles +login anonymous +app_update $STEAM_ID validate +quit
	if [ $? -ne 0 ]; then
		echo "Game update failed, not starting"
		exit 1
	fi
}

RUNNING=0
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		RUNNING=1
	fi
done
if [ $RUNNING -eq 0 ]; then
	update_game
else
	echo "Game server is already running, not updating"
fi

for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-enabled $MAP)" == "enabled" -a "$(systemctl is-active $MAP)" == "inactive" ]; then
		start_game $MAP
	fi
done