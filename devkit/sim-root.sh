#!/bin/sh

SIMULATOR_ID=$(xcrun simctl list devices available | grep -E Booted | sed "s/^[ \t]*//" | awk '{print $3}' | sed 's/[()]//g')
SIMULATOR_DATA_PATH=$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data

ln -sfn .. $SIMULATOR_DATA_PATH/var/mobile

echo $SIMULATOR_DATA_PATH
