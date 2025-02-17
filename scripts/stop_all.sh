#!/bin/bash
#
# Stop all ARK server maps that are enabled
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# List of all maps available on this platform
# compile:noescape
GAME_MAPS="$GAME_MAPS"
# compile:escape

function stop_game {
	echo "Stopping game instance $1..."
	sudo systemctl stop $1
	echo "Waiting 10 seconds for threads to settle"
	for i in {0..9}; do
		echo -n '.'
		sleep 1
	done
	# Check status real quick
	sudo systemctl status $1 | grep Active
}

for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-enabled $MAP)" == "enabled" -a "$(systemctl is-active $MAP)" == "active" ]; then
		stop_game $MAP
	fi
done