#!/usr/bin/env python3

import argparse
import contextlib
import io
import os
import sys
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Transcribe audio with mlx-whisper.")
    parser.add_argument("--audio-path", required=True, help="Path to the input audio file.")
    parser.add_argument(
        "--model",
        default="mlx-community/whisper-large-v3-turbo",
        help="MLX Whisper model path or Hugging Face repo.",
    )
    parser.add_argument(
        "--language",
        default="auto",
        help="Language code. Use 'auto' to let the model detect it.",
    )
    return parser


def extend_path() -> None:
    candidate_paths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        str(Path.home() / "anaconda3" / "bin"),
    ]

    existing = os.environ.get("PATH", "").split(os.pathsep) if os.environ.get("PATH") else []
    merged = []

    for path in candidate_paths + existing:
        if path and path not in merged:
            merged.append(path)

    os.environ["PATH"] = os.pathsep.join(merged)


def configure_environment() -> Path:
    root_dir = Path(__file__).resolve().parent.parent
    hf_home = root_dir / ".cache" / "huggingface"
    hf_home.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("HF_HOME", str(hf_home))
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    extend_path()
    return root_dir


def transcribe(audio_path: str, model: str, language: str) -> str:
    import mlx_whisper

    kwargs = {
        "path_or_hf_repo": model,
    }

    if language.lower() != "auto":
        kwargs["language"] = language

    transcript_output = io.StringIO()
    with contextlib.redirect_stdout(transcript_output), contextlib.redirect_stderr(transcript_output):
        try:
            result = mlx_whisper.transcribe(audio_path, verbose=False, **kwargs)
        except TypeError:
            result = mlx_whisper.transcribe(audio_path, **kwargs)

    text = result.get("text", "")
    return text.strip()


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    configure_environment()

    try:
        text = transcribe(args.audio_path, args.model, args.language)
    except Exception as error:
        print(f"mlx-whisper transcription failed: {error}", file=sys.stderr)
        return 1

    if not text:
        print("mlx-whisper transcription returned empty text", file=sys.stderr)
        return 1

    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
