#!/usr/bin/env python3

import argparse
import contextlib
import io
import json
import os
import re
import sys
import traceback
from pathlib import Path
from typing import Optional


WHISPER_MODEL_ALIASES = {
    "mlx-community/whisper-medium": "mlx-community/whisper-medium-mlx",
    "mlx-community/whisper-small": "mlx-community/whisper-small-mlx",
    "mlx-community/whisper-tiny": "mlx-community/whisper-tiny-mlx",
}

PUNCTUATION_SYSTEM_APPENDIX = """When adding punctuation:
- Preserve every original word in the same order.
- Never translate English into Chinese.
- Never translate Chinese into English.
- Never add or remove content except safe punctuation and spacing around punctuation.
- Keep English words separated by spaces.
- Do not insert spaces between Chinese and English words.
- Use Chinese punctuation after Chinese text.
- Use English punctuation after English text.
- Add one space after English punctuation when another token follows.
- Do not add spaces after Chinese punctuation.

Examples:
Input: 标点符号还是不行请继续用这个sample测试直到它可以正确加上标点
Output: 标点符号还是不行。请继续用这个sample测试，直到它可以正确加上标点。

Input: 今天review API docs然后更新settings页面
Output: 今天review API docs，然后更新settings页面。

Input: Should the app open the browser directly instead of keeping the native setup window for onboarding
Output: Should the app open the browser directly instead of keeping the native setup window for onboarding?
"""

PUNCTUATION_USER_APPENDIX = """Add sentence boundaries and punctuation when it is clearly helpful and safe.
Do not rewrite, summarize, or improve word choice.
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Persistent VoicePower worker.")
    parser.add_argument("--hf-home", help="Override HF_HOME for model cache placement.")
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


def configure_environment(hf_home_override: Optional[str]) -> None:
    root_dir = Path(__file__).resolve().parent.parent
    hf_home = Path(hf_home_override) if hf_home_override else root_dir / ".cache" / "huggingface"
    hf_home.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("HF_HOME", str(hf_home))
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    extend_path()


def download_whisper_model(model: str) -> str:
    model = WHISPER_MODEL_ALIASES.get(model, model)
    if os.path.exists(model):
        return model

    from huggingface_hub import snapshot_download

    return snapshot_download(
        repo_id=model,
        ignore_patterns=["*.onnx", "*.msgpack"],
    )


def download_cleanup_model(model: str) -> str:
    if os.path.exists(model):
        return model

    from huggingface_hub import snapshot_download

    return snapshot_download(
        repo_id=model,
        ignore_patterns=["*.onnx", "*.msgpack"],
    )


def normalize_transcript(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip())


def is_qwen3_model(model_path_or_repo: str) -> bool:
    return "qwen3" in model_path_or_repo.lower()


def cleanup_output(text: str) -> str:
    cleaned = text.strip()
    cleaned = re.sub(r"<think>.*?</think>", "", cleaned, flags=re.DOTALL).strip()
    if cleaned.startswith("Output:"):
        cleaned = cleaned[len("Output:") :].strip()
    return cleaned


def build_cleanup_prompt(raw_text: str, system_prompt: str, user_prompt_template: str, auto_punctuation: bool) -> tuple[str, str]:
    final_system_prompt = system_prompt.strip()
    final_user_prompt = user_prompt_template.replace("{{text}}", raw_text)

    if auto_punctuation:
        final_system_prompt = f"{final_system_prompt}\n\n{PUNCTUATION_SYSTEM_APPENDIX}".strip()
        final_user_prompt = f"{PUNCTUATION_USER_APPENDIX}\n\n{final_user_prompt}".strip()
    else:
        final_system_prompt = (
            f"{final_system_prompt}\n"
            "Do not add punctuation unless the original transcript already makes it obvious."
        ).strip()

    return final_system_prompt, final_user_prompt


class WorkerState:
    def __init__(self) -> None:
        self.whisper_model_id: Optional[str] = None
        self.whisper_model_path: Optional[str] = None
        self.cleanup_model_id: Optional[str] = None
        self.cleanup_model_path: Optional[str] = None
        self.cleanup_model = None
        self.cleanup_tokenizer = None

    def prepare(self, whisper_model: Optional[str], cleanup_enabled: bool, cleanup_model: Optional[str]) -> dict:
        if whisper_model:
            self._ensure_whisper_loaded(whisper_model)

        if cleanup_enabled and cleanup_model:
            self._ensure_cleanup_loaded(cleanup_model)
        else:
            self._unload_cleanup()

        return {"status": "ready"}

    def health(self) -> dict:
        return {
            "status": "ready",
            "whisperModel": self.whisper_model_id,
            "cleanupModel": self.cleanup_model_id,
        }

    def transcribe(self, audio_path: str, whisper_model: str, language: str) -> dict:
        import mlx_whisper

        resolved_model = self._ensure_whisper_loaded(whisper_model)
        kwargs = {
            "path_or_hf_repo": resolved_model,
            "verbose": False,
        }
        if language.lower() != "auto":
            kwargs["language"] = language

        transcript_output = io.StringIO()
        with contextlib.redirect_stdout(transcript_output), contextlib.redirect_stderr(transcript_output):
            result = mlx_whisper.transcribe(audio_path, **kwargs)

        text = normalize_transcript(result.get("text", ""))
        if not text:
            raise RuntimeError("Whisper returned empty text")

        return {"text": text}

    def polish(
        self,
        raw_text: str,
        cleanup_model: str,
        system_prompt: str,
        user_prompt_template: str,
        temperature: float,
        auto_punctuation: bool,
        max_tokens: int,
    ) -> dict:
        if not raw_text.strip():
            return {"text": raw_text}

        model_path = self._ensure_cleanup_loaded(cleanup_model)
        prompt_system, prompt_user = build_cleanup_prompt(
            raw_text,
            system_prompt=system_prompt,
            user_prompt_template=user_prompt_template,
            auto_punctuation=auto_punctuation,
        )

        generated_text = self._generate_cleanup_text(
            model_path_or_repo=model_path,
            system_prompt=prompt_system,
            user_prompt=prompt_user,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        cleaned = cleanup_output(generated_text)
        if not cleaned:
            raise RuntimeError("Cleanup model returned empty text")

        return {"text": cleaned}

    def _ensure_whisper_loaded(self, model_id: str) -> str:
        resolved_model = download_whisper_model(model_id)
        if resolved_model != self.whisper_model_path:
            import mlx.core as mx
            from mlx_whisper.transcribe import ModelHolder

            ModelHolder.get_model(resolved_model, mx.float16)
            self.whisper_model_id = model_id
            self.whisper_model_path = resolved_model

        return resolved_model

    def _ensure_cleanup_loaded(self, model_id: str) -> str:
        resolved_model = download_cleanup_model(model_id)
        if resolved_model != self.cleanup_model_path:
            from mlx_lm import load

            self.cleanup_model, self.cleanup_tokenizer = load(resolved_model)
            self.cleanup_model_id = model_id
            self.cleanup_model_path = resolved_model

        return resolved_model

    def _unload_cleanup(self) -> None:
        self.cleanup_model_id = None
        self.cleanup_model_path = None
        self.cleanup_model = None
        self.cleanup_tokenizer = None

    def _generate_cleanup_text(
        self,
        model_path_or_repo: str,
        system_prompt: str,
        user_prompt: str,
        temperature: float,
        max_tokens: int,
    ) -> str:
        from mlx_lm import generate
        try:
            from mlx_lm.sample_utils import make_sampler
        except ImportError:
            make_sampler = None

        if self.cleanup_model is None or self.cleanup_tokenizer is None:
            raise RuntimeError("Cleanup model is not loaded")

        prompt = f"{system_prompt}\n\n{user_prompt}"
        tokenizer = self.cleanup_tokenizer

        if hasattr(tokenizer, "apply_chat_template") and getattr(tokenizer, "chat_template", None):
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ]
            apply_kwargs = {
                "tokenize": False,
                "add_generation_prompt": True,
            }

            if is_qwen3_model(model_path_or_repo):
                try:
                    prompt = tokenizer.apply_chat_template(messages, enable_thinking=False, **apply_kwargs)
                except TypeError:
                    messages[-1] = {"role": "user", "content": f"/no_think\n{user_prompt}"}
                    prompt = tokenizer.apply_chat_template(messages, **apply_kwargs)
            else:
                prompt = tokenizer.apply_chat_template(messages, **apply_kwargs)

        generate_kwargs = {
            "prompt": prompt,
            "verbose": False,
            "max_tokens": max_tokens,
        }

        last_error = None

        if make_sampler is not None:
            try:
                response = generate(
                    self.cleanup_model,
                    tokenizer,
                    sampler=make_sampler(temp=temperature),
                    **generate_kwargs,
                )
                return str(response).strip()
            except TypeError as error:
                last_error = error

        for argument_name in ("temperature", "temp"):
            try:
                response = generate(
                    self.cleanup_model,
                    tokenizer,
                    **{argument_name: temperature},
                    **generate_kwargs,
                )
                return str(response).strip()
            except TypeError as error:
                last_error = error

        if last_error is not None:
            raise last_error

        raise RuntimeError("Cleanup generation failed")


def make_response(request_id: str, ok: bool, result: Optional[dict] = None, error: Optional[str] = None) -> str:
    payload = {
        "id": request_id,
        "ok": ok,
        "result": result,
        "error": error,
    }
    return json.dumps(payload, ensure_ascii=False)


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    configure_environment(args.hf_home)

    worker = WorkerState()

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue

        request_id = ""
        try:
            request = json.loads(line)
            request_id = str(request.get("id", ""))
            method = request.get("method")

            if method == "prepare":
                result = worker.prepare(
                    whisper_model=request.get("whisperModel"),
                    cleanup_enabled=bool(request.get("cleanupEnabled")),
                    cleanup_model=request.get("cleanupModel"),
                )
            elif method == "reload_models":
                result = worker.prepare(
                    whisper_model=request.get("whisperModel"),
                    cleanup_enabled=bool(request.get("cleanupEnabled")),
                    cleanup_model=request.get("cleanupModel"),
                )
            elif method == "transcribe":
                result = worker.transcribe(
                    audio_path=request["audioPath"],
                    whisper_model=request["whisperModel"],
                    language=request.get("language", "auto"),
                )
            elif method == "polish":
                result = worker.polish(
                    raw_text=request.get("text", ""),
                    cleanup_model=request["cleanupModel"],
                    system_prompt=request["systemPrompt"],
                    user_prompt_template=request["userPromptTemplate"],
                    temperature=float(request.get("temperature", 0.0)),
                    auto_punctuation=bool(request.get("autoPunctuation", True)),
                    max_tokens=int(request.get("maxTokens", 256)),
                )
            elif method == "health":
                result = worker.health()
            elif method == "shutdown":
                result = {"status": "stopping"}
                sys.stdout.write(make_response(request_id, True, result=result) + "\n")
                sys.stdout.flush()
                return 0
            else:
                raise RuntimeError(f"Unknown worker method: {method}")

            sys.stdout.write(make_response(request_id, True, result=result) + "\n")
            sys.stdout.flush()
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            sys.stderr.flush()
            sys.stdout.write(make_response(request_id, False, error=str(error)) + "\n")
            sys.stdout.flush()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
