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
import shutil
from urllib.parse import urlparse

# --- FIX FOR CURL | PYTHON INTERACTIVITY ---
# This reconnects sys.stdin to the terminal (/dev/tty) if the script
# is being piped in. This allows input() to work.
if not sys.stdin.isatty():
    try:
        # Linux / macOS
        sys.stdin = open("/dev/tty")
    except OSError:
        try:
            # Windows
            sys.stdin = open("CON")
        except OSError:
            # If we can't find a terminal, we can't be interactive.
            pass

# --- Configuration & Defaults ---
SAVE_DIR = os.path.expanduser("~/Pictures/wallpapers")
CATEGORY = ""
current_os = platform.system()
DELAY_MINUTES = 10
CLEAN_INSTALL = False

# State flags
category_set_by_arg = False
delay_set_by_arg = False
clean_set_by_arg = False

# Colors
BOLD = "\033[1m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"

def force_print(msg):
    print(msg, flush=True)

def kill_existing_process():
    try:
        if current_os == "Linux":
            pid_bytes = subprocess.check_output(["pgrep", "-f", "WallpaperCarousel"])
            pids = pid_bytes.decode().strip().split()
            for pid in pids:
                subprocess.run(["pkill", "-P", pid], stderr=subprocess.DEVNULL)
                subprocess.run(["kill", pid], stderr=subprocess.DEVNULL)
            if pids:
                force_print("   • Cleaned up old instances.")
        elif current_os == "Windows":
             subprocess.run(["taskkill", "/F", "/IM", "powershell.exe"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def show_help():
    help_text = f"""
{BOLD}WALLPAPER DOWNLOADER{RESET}
---------------------------------------------------
USAGE:
    curl ... | python3 - [OPTIONS]

OPTIONS:
    {CYAN}--category=NAME{RESET}   Fetch specific category.
    {CYAN}--delay=MINUTES{RESET}   Set slideshow interval.
    {CYAN}--clean{RESET}           Delete existing wallpapers.
    {CYAN}--stop{RESET}            Stop background process.
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
    elif arg.startswith("--clean"):
        CLEAN_INSTALL = True
        clean_set_by_arg = True
    elif arg.startswith("--category="):
        CATEGORY = arg.split("=", 1)[1]
        category_set_by_arg = True
    elif arg.startswith("--delay="):
        try:
            DELAY_MINUTES = int(arg.split("=", 1)[1])
            delay_set_by_arg = True
        except ValueError:
            sys.exit(1)

# --- Interactive Mode ---
if not clean_set_by_arg:
    force_print(f"\n{BOLD}Do you want to perform a clean install?{RESET}")
    force_print(f"   (Deletes all files in {SAVE_DIR})")
    try:
        choice = input(f"Clean install? [y/N]: ").strip().lower()
        if choice in ('y', 'yes'):
            CLEAN_INSTALL = True
    except EOFError:
        # Fallback if the stdin fix failed
        force_print(f"{YELLOW}Interactive mode failed. Assuming No.{RESET}")

if not category_set_by_arg:
    print(f"\n{BOLD}Which category of wallpapers would you like?{RESET}")
    print(f"  {GREEN}1){RESET} Random / All")
    print(f"  {GREEN}2){RESET} Cars")
    print(f"  {GREEN}3){RESET} Anime")
    print(f"  {GREEN}4){RESET} Nature")
    print(f"  {GREEN}5){RESET} Cyberpunk")
    print(f"  {GREEN}6){RESET} Minimal")
    print(f"  {GREEN}7){RESET} Custom")
    
    try:
        cat_choice = input(f"Select an option [1-7]: ").strip()
        if cat_choice == '1': CATEGORY = ""
        elif cat_choice == '2': CATEGORY = "cars"
        elif cat_choice == '3': CATEGORY = "anime"
        elif cat_choice == '4': CATEGORY = "nature"
        elif cat_choice == '5': CATEGORY = "cyberpunk"
        elif cat_choice == '6': CATEGORY = "minimal"
        elif cat_choice == '7': CATEGORY = input("Enter category name: ").strip()
        else: CATEGORY = ""
    except EOFError:
        CATEGORY = ""

if not delay_set_by_arg:
    try:
        print(f"\n{BOLD}How many minutes should each wallpaper stay?{RESET}")
        d_input = input(f"Enter minutes [Default: 10]: ").strip()
        if d_input.isdigit():
            DELAY_MINUTES = int(d_input)
    except EOFError:
        pass

# --- Execution ---
DELAY_SECONDS = DELAY_MINUTES * 60
clean_msg = f"{RED}Yes (Wipe){RESET}" if CLEAN_INSTALL else f"{GREEN}No (Keep){RESET}"

force_print(f"\n{CYAN}Configuration:{RESET}")
force_print(f"   Category: {BOLD}{CATEGORY if CATEGORY else 'All'}{RESET}")
force_print(f"   Delay:    {BOLD}{DELAY_MINUTES}m{RESET}")
force_print(f"   Clean:    {clean_msg}")

if not os.path.exists(SAVE_DIR):
    os.makedirs(SAVE_DIR)

if CLEAN_INSTALL:
    force_print(f"\n🧹 {YELLOW}Cleaning up old wallpapers...{RESET}")
    for filename in os.listdir(SAVE_DIR):
        file_path = os.path.join(SAVE_DIR, filename)
        try:
            if os.path.isfile(file_path) or os.path.islink(file_path):
                os.unlink(file_path)
            elif os.path.isdir(file_path):
                shutil.rmtree(file_path)
        except Exception:
            pass

# Fetch and Download
url = f"https://wallpaper-carousel-production.up.railway.app/api/v1/wallpapers?category={CATEGORY}"
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

try:
    force_print("\n🔍 Connecting to server...")
    with urllib.request.urlopen(url, context=ssl_context) as response:
        data = json.loads(response.read().decode())
except Exception:
    force_print(f"{RED}Error: Failed to fetch data.{RESET}")
    sys.exit(1)

wallpapers = data.get("data", {}).get("wallpapers", [])
if not wallpapers:
    force_print(f"{RED}No wallpapers found.{RESET}")
    sys.exit(1)

force_print(f"📂 Downloading {len(wallpapers)} images to {SAVE_DIR}...")

for item in wallpapers:
    if isinstance(item, dict):
        img_url = item.get("imgLink")
    if not img_url:
        continue
    
    filename = os.path.basename(urlparse(img_url).path)
    filepath = os.path.join(SAVE_DIR, filename)
    if not os.path.exists(filepath):
        try:
            with urllib.request.urlopen(img_url, context=ssl_context) as dl_resp, open(filepath, "wb") as out_file:
                out_file.write(dl_resp.read())
            force_print(f"   ↓ {GREEN}Downloaded:{RESET} {filename}")
        except Exception:
             force_print(f"   x {RED}Failed:{RESET} {filename}")
    else:
        force_print(f"   • {YELLOW}Skip:{RESET} {filename}")

# Slideshow Logic
force_print("\n⚙️  Configuring background process...")

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
    shell_cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "-"]
    creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP
else:
    sys.exit(1)

try:
    with urllib.request.urlopen(SETTER_URL, context=ssl_context) as response:
        script_content = re.sub(regex_pattern, replacement_line, response.read())

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
    
    time.sleep(1)
    if proc.poll() is None:
        force_print(f"✅ {BOLD}Slideshow started.{RESET}")
    else:
        force_print(f"{RED}❌ Process failed to start.{RESET}")

except Exception as e:
    force_print(f"{RED}❌ Error: {e}{RESET}")