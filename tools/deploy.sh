#!/usr/bin/env bash
# Copy the trainer from this repo into the local game install (for testing).
# Keeps the player's config.json and diagnostics files in the game folder.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GAME="${MD_GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/Medieval Dynasty}"
MODS="$GAME/Medieval_Dynasty/Binaries/Win64/ue4ss/Mods"

[ -d "$MODS" ] || { echo "UE4SS Mods folder not found: $MODS (set MD_GAME_DIR)" >&2; exit 1; }

mkdir -p "$MODS/DynastyTrainer" "$MODS/shared/ModMenu"
rm -rf "$MODS/DynastyTrainer/Scripts"
cp -r "$REPO/src/DynastyTrainer/Scripts" "$MODS/DynastyTrainer/"
touch "$MODS/DynastyTrainer/enabled.txt"
cp "$REPO/vendor/ModMenu/ModMenu.lua" "$MODS/shared/ModMenu/ModMenu.lua"

echo "Deployed to $MODS/DynastyTrainer"
