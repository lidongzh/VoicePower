#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VoicePower"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RUNTIME_SEED_DIR="$RESOURCES_DIR/RuntimeSeed"
MODULE_CACHE_DIR="$ROOT_DIR/.build/clang-module-cache"
SWIFT_SCAN_CACHE_DIR="$ROOT_DIR/.build/swift-driver-cache"
ICON_MASTER_PNG="$ROOT_DIR/App/VoicePower-icon.png"
ICON_ICNS="$ROOT_DIR/App/VoicePower.icns"
ICON_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voicepower-icon.XXXXXX")"
ICONSET_DIR="$ICON_TMP_DIR/$APP_NAME.iconset"
BUNDLE_RUNTIME=0
RUNTIME_SOURCE_DIR="$HOME/Library/Application Support/VoicePower/Runtime/venv"

for arg in "$@"; do
  case "$arg" in
    --bundle-runtime)
      BUNDLE_RUNTIME=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

cleanup() {
  rm -rf "$ICON_TMP_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE_DIR"
mkdir -p "$SWIFT_SCAN_CACHE_DIR"
rm -rf "$RUNTIME_SEED_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFT_DRIVER_SWIFT_SCAN_CACHE_PATH="$SWIFT_SCAN_CACHE_DIR"

swift "$ROOT_DIR/scripts/generate_app_icon.swift"
mkdir -p "$ICONSET_DIR"

render_icon() {
  local side="$1"
  local name="$2"

  if [[ "$side" == "1024" ]]; then
    cp "$ICON_MASTER_PNG" "$ICONSET_DIR/$name"
    return
  fi

  sips -s format png -z "$side" "$side" "$ICON_MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

render_icon 16 "icon_16x16.png"
render_icon 32 "icon_16x16@2x.png"
render_icon 32 "icon_32x32.png"
render_icon 64 "icon_32x32@2x.png"
render_icon 128 "icon_128x128.png"
render_icon 256 "icon_128x128@2x.png"
render_icon 256 "icon_256x256.png"
render_icon 512 "icon_256x256@2x.png"
render_icon 512 "icon_512x512.png"
render_icon 1024 "icon_512x512@2x.png"

if ! iconutil --convert icns --output "$ICON_ICNS" "$ICONSET_DIR"; then
  if [[ -f "$ICON_ICNS" ]]; then
    echo "iconutil failed; reusing existing $ICON_ICNS" >&2
  else
    echo "iconutil failed and no fallback .icns exists at $ICON_ICNS" >&2
    exit 1
  fi
fi

swift build -c release

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ICON_ICNS" "$RESOURCES_DIR/$APP_NAME.icns"
cp "$ROOT_DIR/scripts/mlx_whisper_transcribe.py" "$RESOURCES_DIR/mlx_whisper_transcribe.py"
cp "$ROOT_DIR/scripts/mlx_cleanup_polish.py" "$RESOURCES_DIR/mlx_cleanup_polish.py"
cp "$ROOT_DIR/scripts/voicepower_worker.py" "$RESOURCES_DIR/voicepower_worker.py"
cp "$ROOT_DIR/scripts/simplify_chinese_text.py" "$RESOURCES_DIR/simplify_chinese_text.py"
cp "$ROOT_DIR/Configuration/voice-power.example.json" "$RESOURCES_DIR/voice-power.example.json"

if [[ "$BUNDLE_RUNTIME" == "1" ]]; then
  if [[ ! -x "$RUNTIME_SOURCE_DIR/bin/python3" ]]; then
    echo "Bundled runtime requested, but no prepared runtime was found at $RUNTIME_SOURCE_DIR" >&2
    exit 1
  fi

  mkdir -p "$RUNTIME_SEED_DIR"
  ditto "$RUNTIME_SOURCE_DIR" "$RUNTIME_SEED_DIR/venv"

  RUNTIME_PYTHON_VERSION="$("$RUNTIME_SOURCE_DIR/bin/python3" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
  RUNTIME_ARCH="$("$RUNTIME_SOURCE_DIR/bin/python3" -c 'import platform; print(platform.machine())')"
  RUNTIME_CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  cat > "$RUNTIME_SEED_DIR/manifest.json" <<EOF
{
  "architecture": "$RUNTIME_ARCH",
  "pythonVersion": "$RUNTIME_PYTHON_VERSION",
  "createdAt": "$RUNTIME_CREATED_AT",
  "seedType": "runtime-only"
}
EOF
fi

chmod +x "$MACOS_DIR/$APP_NAME"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
