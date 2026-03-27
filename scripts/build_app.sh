#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VoicePower"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$ROOT_DIR/.build/clang-module-cache"
SWIFT_SCAN_CACHE_DIR="$ROOT_DIR/.build/swift-driver-cache"

cd "$ROOT_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE_DIR"
mkdir -p "$SWIFT_SCAN_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFT_DRIVER_SWIFT_SCAN_CACHE_PATH="$SWIFT_SCAN_CACHE_DIR"
swift build -c release

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/scripts/mlx_whisper_transcribe.py" "$RESOURCES_DIR/mlx_whisper_transcribe.py"
cp "$ROOT_DIR/scripts/mlx_cleanup_polish.py" "$RESOURCES_DIR/mlx_cleanup_polish.py"
cp "$ROOT_DIR/scripts/simplify_chinese_text.py" "$RESOURCES_DIR/simplify_chinese_text.py"
cp "$ROOT_DIR/Configuration/voice-power.example.json" "$RESOURCES_DIR/voice-power.example.json"
chmod +x "$MACOS_DIR/$APP_NAME"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
