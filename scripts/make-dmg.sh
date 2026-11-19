#!/bin/zsh
# Собирает установочный образ build/wtortoise-<версия>.dmg: приложение + ярлык «Программы».
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-0.1}"
./scripts/bundle.sh

STAGE=build/dmg
DMG="build/wtortoise-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/WTortoise.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "WTortoise $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Установщик: $DMG"
