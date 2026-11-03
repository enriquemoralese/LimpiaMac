#!/bin/bash
# Compila en modo release y arma iClear.app con firma ad hoc (solo para esta Mac).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=iClear.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/iClear "$APP/Contents/MacOS/iClear"
# Se regenera con: swift Recursos/generar_icono.swift icono.png (y luego sips + iconutil)
cp Recursos/iClear.icns "$APP/Contents/Resources/iClear.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>iClear</string>
    <key>CFBundleDisplayName</key><string>iClear</string>
    <key>CFBundleIdentifier</key><string>local.enrique.iClear</string>
    <key>CFBundleExecutable</key><string>iClear</string>
    <key>CFBundleIconFile</key><string>iClear</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Listo: $(pwd)/$APP"
