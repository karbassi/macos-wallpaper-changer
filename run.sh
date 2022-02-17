#!/bin/bash
# Description: Download and set a random wallpaper

# List of random wallpaper services
declare -a URLS=(
	"https://source.unsplash.com/collection/7282015/2560x1600/" # Collection: Wallpapers for macOS
	"https://source.unsplash.com/collection/317099/2560x1600/"  # Collection: Unsplash Editorial
	"https://source.unsplash.com/collection/8961198/2560x1600/" # Collection: Patterns
	"https://source.unsplash.com/2560x1600/?wallpapers"         # Search Term: wallpapers
	"https://source.unsplash.com/2560x1600/?architecture"       # Search Term: architecture
	# "https://source.unsplash.com/user/nasa/2560x1600/"          # User: nasa
	"https://random-google-earth.vercel.app/" # Google Earth
)

# Get random URL from array
RANDOM_INDEX=$((RANDOM % ${#URLS[@]}))
WALLPAPER_SOURCE_URL=${URLS["$RANDOM_INDEX"]}

# Wallpaper download path
WALLPAPER_PATH=$(mktemp -t random-wallpaper.XXXXX)

# Get server response status code
#HTTP_CODE=$(curl --output /dev/null --silent --head --location --write-out "%{http_code}" "$WALLPAPER_SOURCE_URL")

# Check if the wallpaper source URL is valid
#if [ "$HTTP_CODE" != "200" ]; then
#	exit 1
#fi

# Check to make sure curl ran successfully
curl -skLo "$WALLPAPER_PATH" "$WALLPAPER_SOURCE_URL" || exit 1

# Clear old cache
CACHE_FOLDER=$(find /private/var/folders/ -type d -name 'com.apple.desktoppicture' -print -quit 2>/dev/null)

rm -r "$CACHE_FOLDER"/*.png

# Tell OS X to change the wallpaper
osascript -e 'tell application "System Events" to tell every desktop to set picture to "'"$WALLPAPER_PATH"'"'

