#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["ds-store==1.3.3", "mac-alias==2.2.3"]
# ///
"""Writes Resources/DMG/DS_Store, the Finder view that script/release.sh copies
into the release DMG as .DS_Store: the window's size, the icon positions and
the background picture at .background/background.tiff. Run after changing the
layout (positions are icon centers in points from the window's top left, and
must match script/render_dmg_background.swift):

    uv run script/make_dmg_layout.py

Finder finds the picture through an alias, which can only be made for a file on
a mounted volume, so this mounts a throwaway image named Clicker that holds
just the picture. Each release's image is a different volume with different
file IDs, so the alias's IDs are cleared: Finder then resolves it by volume
name and path, which every release shares.
"""

import os
import shutil
import subprocess
import tempfile

from ds_store import DSStore
from mac_alias import Alias

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BACKGROUND = os.path.join(ROOT, "Resources", "DMG", "background.tiff")
OUTPUT = os.path.join(ROOT, "Resources", "DMG", "DS_Store")
VOLUME = "Clicker"
# The window's frame, title bar included: 320 pt of content on macOS 26 and
# later. The picture is 20 pt taller, so macOS 15's shorter title bar shows no
# edge.
WINDOW = (640, 352)
ICON_SIZE = 96
ICONS = {"Clicker.app": (150, 152), "Applications": (490, 152)}


def background_alias():
    with tempfile.TemporaryDirectory() as tmp:
        staging = os.path.join(tmp, "staging")
        os.makedirs(os.path.join(staging, ".background"))
        shutil.copyfile(BACKGROUND, os.path.join(staging, ".background", "background.tiff"))
        image = os.path.join(tmp, "layout.dmg")
        mount = os.path.join(tmp, "mount")
        subprocess.run(
            ["diskutil", "image", "create", "from", "--format", "UDRO", "--volumeName", VOLUME, staging, image],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            ["diskutil", "image", "attach", "--readOnly", "--nobrowse", "--mountPoint", mount, image],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        try:
            # The real path: through the /var symlink the alias would record
            # a path climbing out of the volume.
            alias = Alias.for_file(os.path.realpath(os.path.join(mount, ".background", "background.tiff")))
        finally:
            subprocess.run(["diskutil", "eject", mount], check=True, stdout=subprocess.DEVNULL)
    alias.target.cnid = 0
    alias.target.folder_cnid = 0
    alias.target.cnid_path = []
    return alias.to_bytes()


def main():
    alias = background_alias()
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    with DSStore.open(OUTPUT, "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        # Icon view whatever the user's default, which may be a list with no
        # picture. (dmgbuild's icvl record doesn't do this; Finder ignores it.)
        store["."]["vstl"] = ("type", b"icnv")
        store["."]["bwsp"] = {
            "WindowBounds": "{{400, 280}, {%d, %d}}" % WINDOW,
            "ShowToolbar": False,
            "ShowTabView": False,
            "ShowStatusBar": False,
            "ShowPathbar": False,
            "ShowSidebar": False,
            "ContainerShowSidebar": False,
            "PreviewPaneVisibility": False,
            "SidebarWidth": 0,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 2,
            "backgroundImageAlias": alias,
            "backgroundColorRed": 0.0,
            "backgroundColorGreen": 0.0,
            "backgroundColorBlue": 0.0,
            "arrangeBy": "none",
            "iconSize": float(ICON_SIZE),
            "textSize": 12.0,
            "labelOnBottom": True,
            "showIconPreview": True,
            "showItemInfo": False,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "scrollPositionX": 0.0,
            "scrollPositionY": 0.0,
        }
        for name, position in ICONS.items():
            store[name]["Iloc"] = position
    print(f"wrote {OUTPUT}")


main()
