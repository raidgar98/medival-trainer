#!/usr/bin/env bash
# Build Nexus Mods archives into dist/:
#   ./tools/package.sh            DynastyTrainer-<v>.zip          (trainer only;
#                                 UE4SS and ModMenu are listed as requirements)
#   ./tools/package.sh --bundled  DynastyTrainer-<v>-Bundled.zip  (UE4SS + ModMenu +
#                                 trainer, UE4SS-settings.ini preconfigured)
# Layout is relative to the game folder (Steam > Manage > Browse local files).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -nE 's/^local VERSION = "([^"]+)".*/\1/p' "$REPO/src/DynastyTrainer/Scripts/main.lua")"
[ -n "$VERSION" ] || { echo "VERSION not found in main.lua" >&2; exit 1; }

BUNDLED=0
[ "${1:-}" = "--bundled" ] && BUNDLED=1

# Pinned upstream builds (verified by SHA-256).
UE4SS_NAME="UE4SS_v3.0.1-1185-gdff435dd.zip"
UE4SS_URL="https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental/$UE4SS_NAME"
UE4SS_SHA256="67b81fca6a3eb6e24fe5117d2e390fdc19d49af46dad9500d08106bf9a190d31"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
WIN64="$STAGE/Medieval_Dynasty/Binaries/Win64"
MODS="$WIN64/ue4ss/Mods"

if [ "$BUNDLED" = 1 ]; then
    CACHE="$REPO/dist/cache"
    mkdir -p "$CACHE"
    [ -f "$CACHE/$UE4SS_NAME" ] || curl -fsSL -o "$CACHE/$UE4SS_NAME" "$UE4SS_URL"
    echo "$UE4SS_SHA256  $CACHE/$UE4SS_NAME" | sha256sum -c --quiet
    mkdir -p "$WIN64"
    unzip -q "$CACHE/$UE4SS_NAME" -d "$WIN64"
    # EngineVersionOverride 4 / 27 / Shipping (file uses CRLF line endings).
    INI="$WIN64/ue4ss/UE4SS-settings.ini"
    sed -i -E 's/^MajorVersion =.*\r$/MajorVersion = 4\r/; s/^MinorVersion =.*\r$/MinorVersion = 27\r/; s/^DebugBuild =.*\r$/DebugBuild = false\r/' "$INI"
    grep -q $'^MajorVersion = 4\r$' "$INI" && grep -q $'^MinorVersion = 27\r$' "$INI" && grep -q $'^DebugBuild = false\r$' "$INI" \
        || { echo "Could not set EngineVersionOverride in $INI" >&2; exit 1; }
    mkdir -p "$MODS/shared/ModMenu"
    cp "$REPO/vendor/ModMenu/ModMenu.lua" "$MODS/shared/ModMenu/"
    cp "$REPO/vendor/ModMenu/LICENSE" "$MODS/shared/ModMenu/LICENSE.txt"
    cp "$REPO/docs/INSTALLATION-Bundled.txt" "$STAGE/INSTALLATION.txt"
    cp "$REPO/docs/THIRD_PARTY-Bundled.txt" "$STAGE/THIRD_PARTY.txt"
    OUT="$REPO/dist/DynastyTrainer-$VERSION-Bundled.zip"
else
    cp "$REPO/docs/INSTALLATION.txt" "$REPO/docs/THIRD_PARTY.txt" "$STAGE/"
    OUT="$REPO/dist/DynastyTrainer-$VERSION.zip"
fi

mkdir -p "$MODS/DynastyTrainer"
cp -r "$REPO/src/DynastyTrainer/Scripts" "$MODS/DynastyTrainer/"
touch "$MODS/DynastyTrainer/enabled.txt"
cp "$REPO/docs/PROTON.txt" "$STAGE/LINUX-STEAMDECK-PROTON.txt"
sed "s/@VERSION@/$VERSION/g" "$REPO/docs/README.txt" > "$STAGE/DynastyTrainer-README.txt"

# Nothing a player generated.
find "$STAGE" \( -name config.json -o -name 'diagnostics*.txt' -o -name '*.orig' \) -delete

rm -f "$OUT"
(cd "$STAGE" && zip -qrX "$OUT" .)
echo "$OUT"
sha256sum "$OUT"
