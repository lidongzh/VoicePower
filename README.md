# VoicePower

VoicePower is a local macOS voice typing prototype for mixed English and Chinese dictation. It records audio from the microphone, runs a local `mlx-whisper` transcription command, optionally sends the raw transcript to a local small LLM for cleanup, normalizes the final text to simplified Chinese when configured, then pastes the result into the active application.

This is intentionally closer to "push to talk and paste" than a full macOS Input Method Editor. For a first version, that tradeoff keeps the implementation small and local while still matching the workflow of tools like Typeless.

VoicePower is a menu bar app. It does not open a normal window or show a Dock icon.

## Whisper vs cleanup

Whisper does not reliably "polish" text. It transcribes speech into readable text and will sometimes smooth out some disfluencies, but it is not a deterministic filler-word remover. If you want to remove "um", repeated starts, or other spoken-noise artifacts without changing meaning, a second cleanup step is still useful.

For mixed English and Chinese, use a multilingual Whisper model. In practice, `large-v3-turbo` is the safest starting point if your machine can handle it. `medium` is a smaller fallback, but code-switching accuracy usually drops sooner.

Do not use the `.en` models for this project. For mixed English and Chinese, keep the transcription backend on a multilingual Whisper model and let language detection stay automatic.

## Architecture

The app does four things:

1. Registers a global hotkey.
2. Registers a global right-`Command` hold-to-talk trigger.
3. Records a mono WAV file locally.
4. Queues recordings and processes them one at a time.
5. Runs a local transcription command that you configure in JSON.
6. Optionally calls a local Ollama endpoint to remove filler words and false starts.
7. Optionally normalizes the final text to simplified Chinese.
8. Pastes the result with `Cmd+V`.

The transcription command is still template-based instead of hard-coded, so you can point it at the bundled `mlx-whisper` wrapper or any compatible local wrapper.

## Setup

1. Copy [Configuration/voice-power.example.json](/Users/lidongzh/Documents/RESEARCH_CODE/DEV/voice_power/Configuration/voice-power.example.json) to `~/.voice-power/config.json`.
2. Install the repo-local `mlx-whisper` environment:

```bash
./scripts/install_mlx_whisper.sh
```

3. Edit the JSON so `transcription.command` points to your local Python executable inside the MLX virtualenv and the first transcription argument points at [scripts/mlx_whisper_transcribe.py](/Users/lidongzh/Documents/RESEARCH_CODE/DEV/voice_power/scripts/mlx_whisper_transcribe.py).
   If you want guaranteed simplified Chinese output, also point `normalization.command` at the same Python executable and `normalization.arguments[0]` at [scripts/simplify_chinese_text.py](/Users/lidongzh/Documents/RESEARCH_CODE/DEV/voice_power/scripts/simplify_chinese_text.py).
4. Optional: run a local Ollama server and pick a small instruct model for cleanup. Keep cleanup temperature low.
5. Build the app:

```bash
swift build
```

6. Run it:

```bash
swift run VoicePower
```

7. Grant:
   - Microphone permission
   - Accessibility permission

The default toggle hotkey in the sample config is `Control + Option + Space`.

The app also supports hold-to-talk on the right `Command` key. Press and hold right `Command`, speak, then release it to stop and enqueue that dictation.

If right `Command` does nothing, grant Input Monitoring permission to the current VoicePower app bundle in `System Settings > Privacy & Security > Input Monitoring`.

If you want a standalone app bundle instead of running from Terminal:

```bash
./scripts/build_app.sh
open dist/VoicePower.app
```

During development, rebuilds replace the app bundle. Re-add Accessibility permission after switching to a newly built unsigned local app if macOS stops trusting the previous grant.

The menu bar app also exposes `Cleanup: On/Off` and `Save Audio: On/Off` toggles. Those settings are written back to the active config file so you do not need to edit JSON by hand.

If you start a second recording while a previous one is still being transcribed or cleaned, VoicePower now processes the recordings in FIFO order instead of letting them race each other.

## Recommended cleanup models

If you enable cleanup, pick a small bilingual instruct model and keep the prompt strict:

- Preserve meaning.
- Do not translate.
- Remove filler words and false starts only when safe.
- Return only the cleaned text.

Qwen-family small instruct models are a reasonable fit for mixed English and Chinese cleanup because they handle both languages well enough for this narrow post-processing task.

## Current limitations

- Text insertion is paste-based, so clipboard restore is best-effort for plain text only.
- The first `mlx-whisper` run will be slower because the model may need to download into the local cache.
- Right-`Command` hold-to-talk depends on Input Monitoring permission in addition to Microphone and Accessibility.
- This is not a true IME yet. It is a global dictation helper.
- No VAD or streaming transcription yet.

## Next steps

Likely improvements after this first pass:

- Streaming transcription.
- Better clipboard preservation.
- Packaged `.app` bundle and signed permissions flow.
- Direct `llama.cpp` or MLX cleanup backend in addition to Ollama.
