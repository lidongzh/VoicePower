#!/usr/bin/env python3

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Optional


DEFAULT_SYSTEM_PROMPT = """You are a bilingual dictation cleanup engine.
Your job is to remove filler words, false starts, duplicated fragments, and obvious speech disfluencies only when it is safe.
Preserve the exact language of each span. Never translate English into Chinese. Never translate Chinese into English.
Keep code-switching intact. If output contains Chinese characters, use simplified Chinese script.
Add punctuation when it is clearly implied by the speaker's phrasing or pauses.
Use Chinese punctuation for Chinese spans and standard English punctuation for English spans when natural.
Do not over-rewrite or add information.
Return only the cleaned final text.
Example input: um okay 所以 tomorrow we can maybe 再看一下这个 part
Example output: 所以 tomorrow we can 再看一下这个 part.
Example input: uh I think 这个 bug should be fixed today because it blocks login
Example output: I think 这个 bug should be fixed today, because it blocks login.
Example input: 这个东西为什么不会自己加上标点符号呢如果我想disable这个cleanup model该怎么做呢
Example output: 这个东西为什么不会自己加上标点符号呢？如果我想 disable 这个 cleanup model，该怎么做呢？"""

DEFAULT_USER_PROMPT = """Clean up this dictated text without changing meaning.
Keep mixed English and Chinese intact.
Add punctuation only when it is clearly helpful and safe.
Return only the final cleaned text.

Raw transcript:
{{text}}"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Clean up dictated text with a local MLX model.")
    parser.add_argument(
        "--model",
        default="mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        help="MLX LLM path or Hugging Face repo.",
    )
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--max-tokens", type=int, default=192)
    parser.add_argument("--system-prompt", default=DEFAULT_SYSTEM_PROMPT)
    parser.add_argument("--user-prompt-template", default=DEFAULT_USER_PROMPT)
    parser.add_argument("--hf-home", help="Override HF_HOME for model cache placement.")
    parser.add_argument("--download-only", action="store_true")
    parser.add_argument("--enable-punctuation", action="store_true")
    parser.add_argument("--disable-punctuation", action="store_true")
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


def download_model(model: str) -> str:
    if os.path.exists(model):
        return model

    from huggingface_hub import snapshot_download

    return snapshot_download(
        repo_id=model,
        ignore_patterns=["*.onnx", "*.msgpack"],
    )


def build_prompt(raw_text: str, system_prompt: str, user_prompt_template: str, enable_punctuation: bool) -> tuple[str, str]:
    punctuation_clause = (
        "Add punctuation when it is safe and helpful, but do not rewrite content."
        if enable_punctuation
        else "Do not add punctuation unless the original transcript already makes it obvious. Preserve the transcript almost verbatim."
    )
    final_system_prompt = f"{system_prompt}\n{punctuation_clause}"
    final_user_prompt = user_prompt_template.replace("{{text}}", raw_text)
    return final_system_prompt, final_user_prompt


def is_qwen3_model(model_path_or_repo: str) -> bool:
    return "qwen3" in model_path_or_repo.lower()


def generate_text(
    raw_text: str,
    model_path_or_repo: str,
    system_prompt: str,
    user_prompt_template: str,
    temperature: float,
    max_tokens: int,
    enable_punctuation: bool,
) -> str:
    from mlx_lm import generate, load

    model, tokenizer = load(model_path_or_repo)
    system_prompt, user_prompt = build_prompt(raw_text, system_prompt, user_prompt_template, enable_punctuation)
    prompt = f"{system_prompt}\n\n{user_prompt}"

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

    response = generate(
        model,
        tokenizer,
        prompt=prompt,
        verbose=False,
        max_tokens=max_tokens,
        temp=temperature,
    )
    return str(response).strip()


def cleanup_output(text: str) -> str:
    cleaned = text.strip()
    cleaned = re.sub(r"<think>.*?</think>", "", cleaned, flags=re.DOTALL).strip()
    if cleaned.startswith("Output:"):
        cleaned = cleaned[len("Output:") :].strip()
    return cleaned


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    configure_environment(args.hf_home)

    try:
        resolved_model = download_model(args.model)
    except Exception as error:
        print(f"cleanup model download failed: {error}", file=sys.stderr)
        return 1

    if args.download_only:
        print(resolved_model)
        return 0

    raw_text = sys.stdin.read().strip()
    if not raw_text:
        return 0

    enable_punctuation = True
    if args.disable_punctuation:
        enable_punctuation = False
    if args.enable_punctuation:
        enable_punctuation = True

    try:
        generated_text = generate_text(
            raw_text=raw_text,
            model_path_or_repo=resolved_model,
            system_prompt=args.system_prompt,
            user_prompt_template=args.user_prompt_template,
            temperature=args.temperature,
            max_tokens=args.max_tokens,
            enable_punctuation=enable_punctuation,
        )
    except Exception as error:
        print(f"cleanup model inference failed: {error}", file=sys.stderr)
        return 1

    cleaned = cleanup_output(generated_text)
    if not cleaned:
        print("cleanup model returned empty text", file=sys.stderr)
        return 1

    print(cleaned)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
