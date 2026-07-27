#!/bin/bash
set -e

# Fetch PUID/PGID from environment or fallback to defaults
PUID=${PUID:-1000}
PGID=${PGID:-1000}
UMASK=${UMASK:-002}

# Dynamically adjust group ID for qbtgroup
if getent group qbtgroup >/dev/null 2>&1; then
    groupmod -o -g "$PGID" qbtgroup
else
    groupadd -o -g "$PGID" qbtgroup
fi

# Dynamically adjust user ID and group for qbtuser
if id -u qbtuser >/dev/null 2>&1; then
    usermod -o -u "$PUID" -g "$PGID" qbtuser
else
    useradd -o -u "$PUID" -g "$PGID" -d /data -s /bin/false qbtuser
fi

# Apply system umask for group-write access (002 gives 775 dirs / 664 files)
umask "$UMASK"

# Create necessary directories
mkdir -p /data/qBittorrent /data/filebot/logs

# Copy default config file if not exists
if [ ! -f /data/qBittorrent/qBittorrent.conf ]; then
    cp /src/qBittorrent_default.conf /data/qBittorrent/qBittorrent.conf
fi

# If user customized script, don't touch it
script=/data/filebot/fb.sh
if [ ! -f "$script" ] || [ -z "$(grep "custom=1" "$script")" ]; then
    cp /src/fb.sh /data/filebot
fi

# Download and extract latest VueTorrent
if [ ! -d "/data/qBittorrent/vuetorrent" ]; then
    echo "Downloading latest VueTorrent release..."
    VUETORRENT_URL=$(curl -s https://api.github.com/repos/VueTorrent/VueTorrent/releases/latest \
      | grep browser_download_url \
      | grep vuetorrent.zip \
      | cut -d '"' -f 4)

    if [ -n "$VUETORRENT_URL" ]; then
        curl -L "$VUETORRENT_URL" -o /tmp/vuetorrent.zip
        unzip /tmp/vuetorrent.zip -d /data/qBittorrent
        rm /tmp/vuetorrent.zip
        echo "VueTorrent successfully installed in /data/qBittorrent."
    else
        echo "⚠️ Failed to fetch VueTorrent URL."
    fi
fi

# Set proper ownership on internal application directories
chown -R qbtuser:qbtgroup /data /filebot
chmod +x /data/filebot/fb.sh

# Set the license
license=$(find /data/ -iname "*.psm" | head -n1)
if [ -n "${license}" ]; then
    sh /filebot/filebot.sh --license="${license}"
else
    echo -e "********\n\n>> No license detected for FILEBOT\n>> Please put your license psm file in /data/filebot folder\n\n********\n"
fi

# Set extra filebot parameters
if [ -n "${EXTRA_FILEBOT_PARAM}" ]; then
    sed -i '/output/a "${EXTRA_FILEBOT_PARAM}" \\' /data/filebot/fb.sh
else
    sed -i '/EXTRA_FILEBOT_PARAM/d' /data/filebot/fb.sh
fi

# Path to the config sync script
CONFIG_SYNC_SCRIPT="/apps/qbittorrent-config-sync.py"

if [ "${DISABLE_CONFIG_OVERWRITE}" = "true" ]; then
    echo "DISABLE_CONFIG_OVERWRITE is set to true, skipping configuration sync."
else
    echo "Starting qBittorrent configuration sync..."
    python3 "$CONFIG_SYNC_SCRIPT"
    echo "Configuration sync completed."
fi

# Start qBittorrent under qbtuser with updated PUID/PGID
echo "Starting qBittorrent with UID: $PUID, GID: $PGID, UMASK: $UMASK..."
exec gosu qbtuser:qbtgroup qbittorrent-nox