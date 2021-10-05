#!/bin/bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PLIST="$SCRIPT_DIR/com.karbassi.wallpaper.changer.plist"
RUN_SH=$(echo "$SCRIPT_DIR/run.sh" | sed 's/\//\\\//g')

cp "$PLIST.sample" "$PLIST"
sed -i '' "s/PATH_TO_RUN_SH/$RUN_SH/g" "$PLIST"
mv com.karbassi.wallpaper.changer.plist ~/Library/LaunchAgents
launchctl load -w "$HOME/Library/LaunchAgents/com.karbassi.wallpaper.changer.plist"
