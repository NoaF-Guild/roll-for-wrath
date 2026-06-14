#!/usr/bin/env bash
set -euo pipefail

# Package the roll-for-wrath addon for release.
# Produces roll-for-wrath.zip with a single top-level folder matching the
# addon's .toc file name, which is what WoW expects.

VERSION="${1:-dev}"
ZIP_NAME="roll-for-wrath.zip"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE=$(mktemp -d)
ADDON_DIR="$STAGE/roll-for-wrath"

cleanup() {
	rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$ADDON_DIR/src" "$ADDON_DIR/libs/wotlk"

# Core addon files
cp "$PROJECT_ROOT/roll-for-wrath.toc" \
	"$PROJECT_ROOT/main.lua" \
	"$PROJECT_ROOT/Bindings.xml" \
	"$ADDON_DIR/"

# Media directories
cp -r "$PROJECT_ROOT/assets" "$PROJECT_ROOT/SoftRes" "$ADDON_DIR/"

# Source: shared core + WotLK compat only
find "$PROJECT_ROOT/src" -maxdepth 1 -type f -name '*.lua' -exec cp {} "$ADDON_DIR/src/" \;
cp -r "$PROJECT_ROOT/src/wotlk" "$ADDON_DIR/src/"

# Libraries: WotLK only; drop LibDeflate test/example dirs
rsync -a --exclude='tests' --exclude='examples' \
	"$PROJECT_ROOT/libs/wotlk/" "$ADDON_DIR/libs/wotlk/"

# Set version in the staged TOC before zipping
sed -i "s/^## Version: .*/## Version: $VERSION/" "$ADDON_DIR/roll-for-wrath.toc"

cd "$STAGE"
zip -r "$ZIP_NAME" roll-for-wrath/
mv "$STAGE/$ZIP_NAME" "$PROJECT_ROOT/$ZIP_NAME"

echo "Packaged $PROJECT_ROOT/$ZIP_NAME"
