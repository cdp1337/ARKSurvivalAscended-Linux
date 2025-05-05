#!/bin/bash
#
# Backup all player data
#
# DYNAMICALLY GENERATED FILE! Edit at your own risk

# compile:noescape
GAME_MAPS="$GAME_MAPS"
GAME_USER="$GAME_USER"
GAME_DIR="$GAME_DIR"
SAVE_DIR="$GAME_DIR/AppFiles/ShooterGame/Saved"
# compile:escape

# Check if any maps are running; do not update an actively running server.
RUNNING=0
for MAP in $GAME_MAPS; do
	if [ "$(systemctl is-active $MAP)" == "active" ]; then
		echo "WARNING - $MAP is still running"
		RUNNING=1
	fi
done

if [ $RUNNING -eq 1 ]; then
	echo "At least one map is still running, do you still want to backup? (y/N): "
	read UP
	if [ "$UP" != "y" -a "$UP" != "Y" ]; then
		exit 1
	fi
fi

# Prep the various directories
[ -e $SAVE_DIR/.services ] || mkdir $SAVE_DIR/.services
[ -e $GAME_DIR/backups ] || mkdir $GAME_DIR/backups

# Copy service files from systemd
cp /etc/systemd/system/ark-*.service.d $SAVE_DIR/.services -r

FILES="clusters Config/WindowsServer .services SavedArks"
TGZ="$GAME_DIR/backups/ArkSurvivalAscended-$(date +%Y-%m-%d_%H-%M).tgz"

tar -czf $TGZ \
	-C $SAVE_DIR  \
	--exclude='*_WP_0*.ark' \
	--exclude='*_WP_1*.ark' \
	--exclude='*.profilebak' \
	--exclude='*.tribebak' \
	$FILES

if [ $? -eq 0 ]; then
	echo "Created backup $TGZ"
fi

# Cleanup
rm -fr "$SAVE_DIR/.services"