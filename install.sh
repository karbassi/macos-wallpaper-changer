#!/bin/bash
# Description: Install the wallpaper changer

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
FILE_PLIST="$SCRIPT_DIR/com.karbassi.wallpaper.changer.plist"
RUN_SH=$(echo "$SCRIPT_DIR/run.sh" | sed 's/\//\\\//g')

# copy .env.sample to .env
cp "$SCRIPT_DIR/.env.sample" "$SCRIPT_DIR/.env"

# copy plist.sample to plist
cp "$FILE_PLIST.sample" "$FILE_PLIST"

# replace the path to run.sh
sed -i '' "s/PATH_TO_RUN_SH/$RUN_SH/g" "$FILE_PLIST"

# copy plist to LaunchAgents
mv com.karbassi.wallpaper.changer.plist ~/Library/LaunchAgents

# load the plist
launchctl load -w "$HOME/Library/LaunchAgents/com.karbassi.wallpaper.changer.plist"
