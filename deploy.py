"""Copy the addon from this folder into the game, to test it before a release.

Usage:
    python deploy.py            into retail
    python deploy.py ptr        into the retail test realm
    python deploy.py all        into every installed game version

Only the files the game loads are copied. A copy made this way replaces the
one the CurseForge app installed, until the app updates the addon again.
"""
import os
import shutil
import sys

ADDON_NAME = "AutoAcceptInvite"
ADDON_DIR = os.path.dirname(os.path.abspath(__file__))
WOW = r"C:\Program Files (x86)\World of Warcraft"
FILES = ["AutoAcceptInvite.toc", "AutoAcceptInvite.lua"]

# What to type, and the game folder it means.
GAMES = {
    "retail": "_retail_",
    "ptr": "_ptr_",
    "xptr": "_xptr_",
    "era": "_classic_era_",
    "anniversary": "_anniversary_",
    "mists": "_classic_",
    "forever": "_forever_",
}


def deploy(game):
    addons = os.path.join(WOW, GAMES[game], "Interface", "AddOns")
    if not os.path.isdir(addons):
        print("%-12s not installed, skipped" % game)
        return
    target = os.path.join(addons, ADDON_NAME)
    os.makedirs(target, exist_ok=True)
    for name in FILES:
        shutil.copy2(os.path.join(ADDON_DIR, name), os.path.join(target, name))
    print("%-12s %s" % (game, target))


def main():
    asked = sys.argv[1:] or ["retail"]
    games = list(GAMES) if asked == ["all"] else asked
    unknown = [g for g in games if g not in GAMES]
    if unknown:
        sys.exit("Unknown game version: %s. Choose from: %s, all" % (", ".join(unknown), ", ".join(GAMES)))
    for game in games:
        deploy(game)


if __name__ == "__main__":
    main()
