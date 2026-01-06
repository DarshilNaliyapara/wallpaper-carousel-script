import os
import sys
import json
import urllib.request
import urllib.error
import ssl
import subprocess
from urllib.parse import urlparse

SAVE_DIR = os.path.expanduser("~/Pictures/wallpapers")
SETTER_SCRIPT = "./slideshow.sh"
CATEGORY = ""

def show_help():
    """Displays a formatted help message."""
    help_text = """
\033[1mWALLPAPER DOWNLOADER\033[0m
---------------------------------------------------
A script to download wallpapers from the cloud and 
automatically set them as your desktop background.

\033[1mUSAGE:\033[0m
    curl ... | python3 - [OPTIONS]

\033[1mOPTIONS:\033[0m
    \033[36m--category=NAME\033[0m   Fetch wallpapers from a specific category.
                      \033[2mExamples: anime, nature, cyberpunk, minimal\033[0m

    \033[36m-h, --help\033[0m        Show this help message and exit.

\033[1mEXAMPLES:\033[0m
    # Download all wallpapers
    curl -sL ... | python3

    # Download only 'anime' wallpapers
    curl -sL ... | python3 - --category=anime
    """
    print(help_text)

args = sys.argv[1:]
while args:
    arg = args.pop(0)
    if arg in ("-h", "--help"):
        show_help()
        sys.exit(0)
    elif arg.startswith("--category="):
        CATEGORY = arg.split("=", 1)[1]
    else:
        print(f"\033[31mError: Unknown parameter '{arg}'\033[0m")
        print("Try using '-h' for a list of available commands.")
        sys.exit(1)

if not os.path.exists(SAVE_DIR):
    os.makedirs(SAVE_DIR)

url = f"https://wallpaper-carousel-production.up.railway.app/api/v1/wallpapers?category={CATEGORY}"

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

try:
    with urllib.request.urlopen(url, context=ssl_context) as response:
        if response.status != 200:
            print("Error: Failed to fetch data.")
            sys.exit(1)
        data = json.loads(response.read().decode())
except Exception as e:
    print(f"Error: Failed to fetch data. {e}")
    sys.exit(1)

wallpapers = data.get("data", {}).get("wallpapers", [])
print(f"Downloading images to {SAVE_DIR}...")

first_img_path = None

for img_url in wallpapers:
    if not img_url:
        continue

    filename = os.path.basename(urlparse(img_url).path)
    filepath = os.path.join(SAVE_DIR, filename)

    if first_img_path is None:
        first_img_path = filepath

    if not os.path.exists(filepath):
        print(f"   ↓ Downloading: {filename}")
        try:
            with urllib.request.urlopen(img_url, context=ssl_context) as dl_response, open(filepath, 'wb') as out_file:
                out_file.write(dl_response.read())
        except Exception as e:
            print(f"   x Failed to download {filename}: {e}")
    else:
        print(f"   • Skip: {filename}")

if first_img_path and os.path.exists(first_img_path):
    if os.path.exists(SETTER_SCRIPT):
        try:
            subprocess.run([SETTER_SCRIPT], check=False)
        except OSError:
            subprocess.run(["bash", SETTER_SCRIPT], check=False)
    else:
        print(f"Warning: {SETTER_SCRIPT} not found in current directory.")
else:
    print("❌ Could not set wallpaper (file missing).")
    sys.exit(1)
