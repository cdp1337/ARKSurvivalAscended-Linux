#!/bin/bash
#
# Start all ARK server maps that are enabled
# DYNAMICALLY GENERATED FILE! Edit at your own risk
# compile:noescape
GAME_DIR="$GAME_DIR"
# compile:escape

$GAME_DIR/update.sh
$GAME_DIR/manage.py --start-all
