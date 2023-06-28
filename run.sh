#!/bin/bash
# Description: Download and set a random wallpaper

# Unsplash API Client ID from .env file
source "$(dirname "$0")/.env"

# Exit if the client id is not set
if [[ -z "$UNSPLASH_CLIENT_ID" ]]; then
	echo "UNSPLASH_CLIENT_ID is not set in .env file"
	exit 1
fi

# Unsplash API
UNSPLASH_BASE_URL="https://api.unsplash.com"
UNSPLASH_DEFAULT_PARAMS="&content_filter=high&orientation=landscape"
UNSPLASH_URL="${UNSPLASH_BASE_URL}/photos/random?client_id=${UNSPLASH_CLIENT_ID}${UNSPLASH_DEFAULT_PARAMS}"

# List of random wallpaper services
declare -a URLS=(
	"${UNSPLASH_URL}&collections=7282015"     # Collection: Wallpapers for macOS
	"${UNSPLASH_URL}&collections=317099"      # Collection: Unsplash Editorial
	"${UNSPLASH_URL}&collections=8961198"     # Collection: Patterns
	"${UNSPLASH_URL}&query=wallpapers"        # Query: wallpapers
	"${UNSPLASH_URL}&query=architecture"      # Query: architecture
	"${UNSPLASH_URL}&topics=wallpapers"       # Topic: wallpapers
	"${UNSPLASH_URL}&username=nasa"           # User: nasa
	"https://random-google-earth.vercel.app/" # Google Earth
)

# Get random URL from array
RANDOM_INDEX=$((RANDOM % ${#URLS[@]}))
WALLPAPER_SOURCE_URL="${URLS["$RANDOM_INDEX"]}"

# If the url is unsplash, then we need to call the API to get the raw url
if [[ $WALLPAPER_SOURCE_URL == *"unsplash"* ]]; then
	# Call API and get json response, get the first item in the array, and get the raw url
	WALLPAPER_RAW_IMAGE_URL=$(curl -s "$WALLPAPER_SOURCE_URL" | jq -r '.urls.raw')

	# Resize the image to 2560x1600
	WALLPAPER_SOURCE_URL="${WALLPAPER_RAW_IMAGE_URL}&w=2560&h=1600&fit=crop"
fi

# Wallpaper download path
WALLPAPER_PATH=$(mktemp -t random-wallpaper.XXXXX)

# Check to make sure curl ran successfully
curl -skLo "$WALLPAPER_PATH" "$WALLPAPER_SOURCE_URL" || exit 1

# Clear old cache
CACHE_FOLDER=$(find /private/var/folders/ -type d -name 'com.apple.desktoppicture' -print -quit 2>/dev/null)

# Delete all cached wallpapers (PNG files) using find
find "$CACHE_FOLDER" -type f -name '*.png' -delete

# Tell OS X to change the wallpaper
osascript -e 'tell application "System Events" to tell every desktop to set picture to "'"$WALLPAPER_PATH"'"'
