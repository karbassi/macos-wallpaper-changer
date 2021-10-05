#!/bin/bash

declare -a URLS=(
	# "https://source.unsplash.com/collection/7282015/2560x1600/"		# Collection: Wallpapers for macOS
	# "https://source.unsplash.com/collection/317099/2560x1600/"		# Collection: Unsplash Editorial
	# "https://source.unsplash.com/collection/8961198/2560x1600/"		# Collection: Patterns
	# "https://source.unsplash.com/2560x1600/?wallpapers"				# Search Term: wallpapers
	# "https://source.unsplash.com/2560x1600/?architecture"			# Search Term: architecture
	# "https://source.unsplash.com/user/nasa/1600x900"				# User: nasa
	"https://random-google-earth.vercel.app/" # Google Earth
)

WALLPAPER_SOURCE_URL=${URLS["$((RANDOM % ${#URLS[@]}))"]}
WALLPAPER_PATH=$(mktemp "$TMPDIR"/random-wallpaper-"$(uuidgen)".png)
#WALLPAPER_PATH="$HOME/.random-wallpaper.png"

# Check to make sure curl ran successfully
curl -skLo "$WALLPAPER_PATH" "$WALLPAPER_SOURCE_URL" || exit 1

osascript -e 'tell application "System Events" to tell every desktop to set picture to "'"$WALLPAPER_PATH"'"'
