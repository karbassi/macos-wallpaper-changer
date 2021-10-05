#!/bin/bash

PLIST="$HOME/Library/LaunchAgents/com.karbassi.wallpaper.changer.plist"

launchctl unload -w "$PLIST"
rm "$PLIST"
