#!/bin/zsh
# Собирает «WTortoise.app» в build/ (без Xcode, только SwiftPM и swiftc): приложение и расширение Finder в нём.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/WTortoise.app"
APPEX="$APP/Contents/PlugIns/WTortoiseFinder.appex"
VERSION="${VERSION:-0.1}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/ru.lproj" "$APPEX/Contents/MacOS"
cp .build/release/WTortoise "$APP/Contents/MacOS/WTortoise"
cp scripts/askpass.sh "$APP/Contents/Resources/askpass.sh"
chmod +x "$APP/Contents/Resources/askpass.sh"

# Иконка программы: рисуем кодом и собираем .icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swiftc -O -o build/appicon scripts/appicon/main.swift Sources/WTortoise/Shared/Glyphs.swift Sources/WTortoise/Shared/L.swift
build/appicon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Значки команд в PNG — для меню других программ (WExplorer берёт их из Resources/MenuIcons).
swiftc -O -o build/menuicons scripts/menuicons/main.swift Sources/WTortoise/Shared/*.swift
build/menuicons "$APP/Contents/Resources/MenuIcons"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WTortoise</string>
<key>CFBundleDisplayName</key><string>WTortoise</string>
<key>CFBundleIdentifier</key><string>dev.oleg.wtortoise</string>
<key>CFBundleExecutable</key><string>WTortoise</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>dev.oleg.wtortoise.command</string>
  <key>CFBundleURLSchemes</key><array><string>wtortoise</string></array>
</dict></array>
<key>CFBundleDocumentTypes</key><array><dict>
  <key>CFBundleTypeName</key><string>Folder</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSHandlerRank</key><string>None</string>
  <key>LSItemContentTypes</key><array><string>public.folder</string></array>
</dict></array>
<key>NSDesktopFolderUsageDescription</key><string>WTortoise works with Git repositories in your Desktop folder.</string>
<key>NSDocumentsFolderUsageDescription</key><string>WTortoise works with Git repositories in your Documents folder.</string>
<key>NSDownloadsFolderUsageDescription</key><string>WTortoise works with Git repositories in your Downloads folder.</string>
<key>NSRemovableVolumesUsageDescription</key><string>WTortoise works with Git repositories on removable drives.</string>
<key>NSNetworkVolumesUsageDescription</key><string>WTortoise works with Git repositories on network drives.</string>
</dict></plist>
PLIST

# Расширение Finder: меню и значки. Точка входа — NSExtensionMain, поэтому собираем swiftc, а не SwiftPM.
swiftc -O -module-name WTortoiseFinder -parse-as-library -application-extension \
  -target "$(uname -m)-apple-macos13.0" -framework FinderSync \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/WTortoiseFinder" \
  Sources/WTortoiseFinder/*.swift Sources/WTortoise/Shared/*.swift

cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WTortoiseFinder</string>
<key>CFBundleDisplayName</key><string>WTortoise</string>
<key>CFBundleIdentifier</key><string>dev.oleg.wtortoise.finder</string>
<key>CFBundleExecutable</key><string>WTortoiseFinder</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSExtension</key><dict>
  <key>NSExtensionAttributes</key><dict/>
  <key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
  <key>NSExtensionPrincipalClass</key><string>FinderSync</string>
</dict>
</dict></plist>
PLIST

# Сначала расширение со своими правами песочницы, потом приложение целиком.
codesign --force --sign - --entitlements scripts/finder.entitlements "$APPEX"
codesign --force --sign - "$APP"
echo "Готово: $APP"
