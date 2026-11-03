#!/bin/bash
# Compila en modo release y arma LimpiaMac.app con firma ad hoc (solo para esta Mac).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=LimpiaMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LimpiaMac "$APP/Contents/MacOS/LimpiaMac"
# Se regenera con: swift Recursos/generar_icono.swift icono.png (y luego sips + iconutil)
cp Recursos/LimpiaMac.icns "$APP/Contents/Resources/LimpiaMac.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>LimpiaMac</string>
    <key>CFBundleDisplayName</key><string>LimpiaMac</string>
    <key>CFBundleIdentifier</key><string>local.enrique.LimpiaMac</string>
    <key>CFBundleExecutable</key><string>LimpiaMac</string>
    <key>CFBundleIconFile</key><string>LimpiaMac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>LimpiaMac le pide a Finder que vacíe la Papelera cuando tú lo confirmas.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Listo: $(pwd)/$APP"
