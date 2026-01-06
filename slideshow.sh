#!/bin/sh

DIR="$HOME/Pictures/wallpapers"
INTERVAL=120

# Ensure directory exists to prevent errors
if [ ! -d "$DIR" ]; then
    echo "Directory $DIR does not exist."
    exit 1
fi

while true; do

    RANDOM_IMG=$(find "$DIR" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.webp" \) 2>/dev/null | shuf -n 1)

    if [ -n "$RANDOM_IMG" ]; then
        
        # FIX: standard sh way to lowercase string
        raw_de="${XDG_CURRENT_DESKTOP:-}"
        raw_session="${DESKTOP_SESSION:-}"
        
        DE=$(echo "$raw_de" | tr '[:upper:]' '[:lower:]')
        SESSION=$(echo "$raw_session" | tr '[:upper:]' '[:lower:]')
        
        ENV_ID="$DE $SESSION"

        case "$ENV_ID" in
            *hyprland*)
                if command -v swww >/dev/null 2>&1; then
                    if ! pgrep -x "swww-daemon" > /dev/null; then
                        swww-daemon > /dev/null 2>&1 &
                        sleep 1
                    fi
                    swww img "$RANDOM_IMG" --transition-type grow --transition-fps 60
                else
                    echo "❌ Error: 'swww' is not installed."
                    echo "📂 Wallpapers are located at: $DIR"
                    echo "⚠️ Please install swww or set the wallpaper"
                    exit 1
                fi
                ;;
            
            *sway*)
                pkill swaybg
                swaybg -i "$RANDOM_IMG" -m fill &
                ;;
            
            *gnome*|*ubuntu*)
                gsettings set org.gnome.desktop.background picture-uri "file://$RANDOM_IMG"
                gsettings set org.gnome.desktop.background picture-uri-dark "file://$RANDOM_IMG"
                ;;
            
            *kde*|*plasma*)
                dbus-send --session --dest=org.kde.plasmashell --type=method_call /PlasmaShell org.kde.PlasmaShell.evaluateScript 'string:
                    var allDesktops = desktops();
                    for (i=0;i<allDesktops.length;i++) {
                        d = allDesktops[i];
                        d.wallpaperPlugin = "org.kde.image";
                        d.currentConfigGroup = Array("Wallpaper", "org.kde.image", "General");
                        d.writeConfig("Image", "file://'"$RANDOM_IMG"'");
                    }'
                ;;
            
            *xfce*)
                xfconf-query -c xfce4-desktop -l | grep "last-image" | while read property; do
                    xfconf-query -c xfce4-desktop -p "$property" -s "$RANDOM_IMG"
                done
                ;;
            
            *)
                if command -v feh >/dev/null 2>&1; then
                    feh --bg-fill "$RANDOM_IMG"
                elif command -v nitrogen >/dev/null 2>&1; then
                    nitrogen --set-auto "$RANDOM_IMG" --save
                else
                    echo "❌ No supported wallpaper setter found."
                fi
                ;;
        esac

        echo "✅ Set wallpaper: $(basename "$RANDOM_IMG")"
    else
        echo "⚠️  No images found in $DIR"
    fi
    
    sleep "$INTERVAL"
done