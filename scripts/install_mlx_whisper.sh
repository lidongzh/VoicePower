#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv-mlx-whisper"
PIP_CACHE_DIR="$ROOT_DIR/.cache/pip"
HF_HOME_DIR="$ROOT_DIR/.cache/huggingface"
PYTHON_BIN="${PYTHON_BIN:-python3}"

mkdir -p "$PIP_CACHE_DIR" "$HF_HOME_DIR"

if [ ! -x "$VENV_DIR/bin/python3" ]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python3" -m pip install --upgrade pip setuptools wheel
PIP_CACHE_DIR="$PIP_CACHE_DIR" HF_HOME="$HF_HOME_DIR" \
  "$VENV_DIR/bin/python3" -m pip install --upgrade mlx-whisper opencc-python-reimplemented mlx-lm

"$VENV_DIR/bin/python3" - <<'PY'
import mlx_whisper
print("mlx_whisper import ok")
PY

echo "Installed mlx-whisper into $VENV_DIR"
