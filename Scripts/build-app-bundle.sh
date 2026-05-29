#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="$ROOT_DIR/.build/manual"
APP_DIR="$ROOT_DIR/Build/PaperInbox.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"
CLANG_MODULE_CACHE_DIR="$ROOT_DIR/.build/clang-module-cache"
APP_ICON_MASTER="$ROOT_DIR/PaperInbox_AppIcon_Assets/PaperInbox_AppIcon_Master_1024.png"
APP_ICON_TOOL="$BUILD_DIR/make-app-icns"

mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR" "$CLANG_MODULE_CACHE_DIR"

CORE_SOURCES=(
    Sources/PaperInboxCore/Models/*.swift
    Sources/PaperInboxCore/Utilities/*.swift
    Sources/PaperInboxCore/Services/*.swift
    Sources/PaperInboxCore/Database/*.swift
)

APP_SOURCES=(
    Sources/PaperInbox/*.swift
)

swiftc \
    -emit-library \
    -emit-module \
    -emit-module-path "$BUILD_DIR/PaperInboxCore.swiftmodule" \
    -module-name PaperInboxCore \
    -parse-as-library \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -Xcc -fmodules-cache-path="$CLANG_MODULE_CACHE_DIR" \
    -I Sources/SQLiteShim/include \
    "${CORE_SOURCES[@]}" \
    -lsqlite3 \
    -Xlinker -install_name \
    -Xlinker @rpath/libPaperInboxCore.dylib \
    -o "$BUILD_DIR/libPaperInboxCore.dylib"

swiftc \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -Xcc -fmodules-cache-path="$CLANG_MODULE_CACHE_DIR" \
    -I "$BUILD_DIR" \
    -I Sources/SQLiteShim/include \
    -L "$BUILD_DIR" \
    -lPaperInboxCore \
    "${APP_SOURCES[@]}" \
    -lsqlite3 \
    -framework WebKit \
    -Xlinker -rpath \
    -Xlinker @executable_path/../Frameworks \
    -o "$BUILD_DIR/PaperInbox"

cp "$BUILD_DIR/PaperInbox" "$MACOS_DIR/PaperInbox"
cp "$BUILD_DIR/libPaperInboxCore.dylib" "$FRAMEWORKS_DIR/libPaperInboxCore.dylib"
cp "$ROOT_DIR/BuildSupport/PaperInbox-Info.plist" "$CONTENTS_DIR/Info.plist"

if [[ -f "$APP_ICON_MASTER" ]]; then
    swiftc \
        -module-cache-path "$MODULE_CACHE_DIR" \
        -Xcc -fmodules-cache-path="$CLANG_MODULE_CACHE_DIR" \
        "$ROOT_DIR/Scripts/make-app-icns.swift" \
        -framework AppKit \
        -o "$APP_ICON_TOOL"
    "$APP_ICON_TOOL" "$APP_ICON_MASTER" "$RESOURCES_DIR/PaperInbox.icns"
fi

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
