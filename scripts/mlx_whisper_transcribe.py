#!/usr/bin/env python3

import argparse
import contextlib
import io
import os
import sys
from pathlib import Path
from typing import Optional

MODEL_ALIASES = {
    "mlx-community/whisper-medium": "mlx-community/whisper-medium-mlx",
    "mlx-community/whisper-small": "mlx-community/whisper-small-mlx",
    "mlx-community/whisper-tiny": "mlx-community/whisper-tiny-mlx",
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Transcribe audio with mlx-whisper.")
    parser.add_argument("--audio-path", help="Path to the input audio file.")
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
    parser.add_argument(
        "--download-only",
        action="store_true",
        help="Download the model into the local Hugging Face cache without transcribing.",
    )
    parser.add_argument(
        "--hf-home",
        help="Override HF_HOME for model cache placement.",
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


def configure_environment(hf_home_override: Optional[str]) -> Path:
    root_dir = Path(__file__).resolve().parent.parent
    hf_home = Path(hf_home_override) if hf_home_override else root_dir / ".cache" / "huggingface"
    hf_home.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("HF_HOME", str(hf_home))
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    extend_path()
    return root_dir


def download_model(model: str) -> str:
    model = MODEL_ALIASES.get(model, model)
    if os.path.exists(model):
        return model

    from huggingface_hub import snapshot_download

    return snapshot_download(
        repo_id=model,
        ignore_patterns=["*.onnx", "*.msgpack"],
    )


def transcribe(audio_path: str, model: str, language: str) -> str:
    import mlx_whisper

    kwargs = {
        "path_or_hf_repo": MODEL_ALIASES.get(model, model),
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
    configure_environment(args.hf_home)

    if args.download_only:
        try:
            resolved_model = download_model(args.model)
        except Exception as error:
            print(f"mlx-whisper model download failed: {error}", file=sys.stderr)
            return 1

        print(resolved_model)
        return 0

    if not args.audio_path:
        parser.error("--audio-path is required unless --download-only is used")

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
