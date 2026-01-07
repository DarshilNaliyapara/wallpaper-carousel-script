#!/usr/bin/env python3
import os
import platform
import sys
import json
import urllib.request
import urllib.error
import ssl
import subprocess
import re
import time
from urllib.parse import urlparse

if sys.stdout.isatty():

    sys.stdout.reconfigure(line_buffering=True)
else:
  
    try:
        sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buffering=1)
    except OSError:

        pass

SAVE_DIR = os.path.expanduser("~/Pictures/wallpapers")
CATEGORY = ""
current_os = platform.system()
DELAY_SECONDS = 10 * 60


def force_print(msg):
    """Helper to print immediately."""
    print(msg, flush=True)


def kill_existing_process():
    """Finds the WallpaperCarousel process, kills its children (sleep), then kills the script."""
    try:
        pid_bytes = subprocess.check_output(["pgrep", "-f", "WallpaperCarousel"])
        pids = pid_bytes.decode().strip().split()

        for pid in pids:
            subprocess.run(
                ["pkill", "-P", pid],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            subprocess.run(
                ["kill", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

        if pids:
            force_print("   • Cleaned up old instances.")

    except subprocess.CalledProcessError:
        pass
    except Exception as e:
        force_print(f"Warning during cleanup: {e}")


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
    
    \033[36m--delay=MINUTES\033[0m   Set slideshow interval in minutes (Default: 10)

    \033[36m--stop\033[0m            stop wallpaper slidshow process

    \033[36m-h, --help\033[0m        Show this help message and exit.
    """
    force_print(help_text)


# --- Argument Parsing ---
args = sys.argv[1:]
while args:
    arg = args.pop(0)
    if arg in ("-h", "--help"):
        show_help()
        sys.exit(0)
    elif arg.startswith("--stop"):
        kill_existing_process()
        sys.exit(0)
    elif arg.startswith("--category="):
        CATEGORY = arg.split("=", 1)[1]
    elif arg.startswith("--delay="):
        try:
            minutes = int(arg.split("=", 1)[1])
            DELAY_SECONDS = minutes * 60
        except ValueError:
            force_print("Error: Delay must be a number (in minutes).")
            sys.exit(1)
    else:
        force_print(f"\033[31mError: Unknown parameter '{arg}'\033[0m")
        sys.exit(1)

if not os.path.exists(SAVE_DIR):
    os.makedirs(SAVE_DIR)

# --- Fetching Data ---
url = f"https://wallpaper-carousel-production.up.railway.app/api/v1/wallpapers?category={CATEGORY}"
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

try:
    force_print("🔍 Connecting to server (this may take a moment)...")  # <--- ADDED
    with urllib.request.urlopen(url, context=ssl_context) as response:
        if response.status != 200:
            force_print("Error: Failed to fetch data.")
            sys.exit(1)
        data = json.loads(response.read().decode())
except Exception as e:
    force_print(f"Error: Failed to fetch data. {e}")
    sys.exit(1)

wallpapers = data.get("data", {}).get("wallpapers", [])
force_print(f"📂 Downloading {len(wallpapers)} images to {SAVE_DIR}...")

first_img_path = None

for img_url in wallpapers:
    if not img_url:
        continue

    filename = os.path.basename(urlparse(img_url).path)
    filepath = os.path.join(SAVE_DIR, filename)

    if first_img_path is None:
        first_img_path = filepath

    if not os.path.exists(filepath):
        force_print(f"   ↓ Downloading: {filename}")  # <--- UPDATED
        try:
            with urllib.request.urlopen(
                img_url, context=ssl_context
            ) as dl_response, open(filepath, "wb") as out_file:
                out_file.write(dl_response.read())
        except Exception as e:
            force_print(f"   x Failed to download {filename}: {e}")
    else:
        force_print(f"   • Skip: {filename}")

# --- Slideshow Setup ---
if current_os == "Linux":
    SETTER_URL = "https://raw.githubusercontent.com/DarshilNaliyapara/wallpaper-carousel-script/main/slideshow.sh"
    regex_pattern = rb"INTERVAL=\d+"
    replacement_line = f"INTERVAL={DELAY_SECONDS}".encode()
    shell_cmd = ["/bin/sh", "-s", "WallpaperCarousel"]
    creation_flags = 0

elif current_os == "Windows":
    SETTER_URL = "https://raw.githubusercontent.com/DarshilNaliyapara/wallpaper-carousel-script/main/set-slideshow.ps1"
    regex_pattern = rb"\$INTERVAL\s*=\s*\d+"
    replacement_line = f"$INTERVAL={DELAY_SECONDS}".encode()
    shell_cmd = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        "-",
    ]
    creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP
else:
    raise OSError(f"Unsupported OS: {current_os}")

try:
    force_print("⚙️  Configuring background process...")
    with urllib.request.urlopen(SETTER_URL, context=ssl_context) as response:
        script_content = response.read()

    script_content = re.sub(regex_pattern, replacement_line, script_content)

    kill_existing_process()

    proc = subprocess.Popen(
        shell_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True if current_os != "Windows" else False,
        creationflags=creation_flags,
        cwd=SAVE_DIR,
    )

    proc.stdin.write(script_content)
    proc.stdin.close()

    time.sleep(1.0)

    if proc.poll() is None:
        force_print("✅ Slideshow started successfully.")
    else:
        error_msg = proc.stderr.read().decode().strip()
        force_print("❌ Process failed to start.")
        if error_msg:
            force_print(f"Reason: {error_msg}")

except Exception as e:
    force_print(f"❌ Failed to launch slideshow: {e}")
