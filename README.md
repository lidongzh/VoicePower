# VoicePower

VoicePower is a local macOS voice typing prototype for mixed English and Chinese dictation. It records audio from the microphone, bootstraps a local `mlx-whisper` runtime on first launch, optionally runs a local MLX cleanup model, normalizes the final text to simplified Chinese when configured, then pastes the result into the active application.

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
5. Runs a bundled local MLX Whisper worker.
6. Optionally runs a bundled local MLX cleanup worker.
7. Normalizes Chinese output to simplified Chinese.
8. Pastes the result with `Cmd+V`.

## Setup

The new default flow is:

1. Build the app:

```bash
./scripts/build_app.sh
```

To build a GitHub-release style disk image instead:

```bash
./scripts/build_dmg.sh
```

2. Open `dist/VoicePower.app` or distribute `dist/VoicePower.dmg`.
3. Grant:
   - Microphone permission
   - Accessibility permission
   - Input Monitoring permission if you want right-`Command` hold-to-talk
4. Wait for the menu bar app to finish preparing the local runtime and Whisper model.
5. Optional: turn `Cleanup: On` in the menu. The app will download the cleanup model on demand.

If `~/.voice-power/config.json` does not exist yet, VoicePower creates it automatically on first launch using [Configuration/voice-power.example.json](/Users/lidongzh/Documents/RESEARCH_CODE/DEV/voice_power/Configuration/voice-power.example.json) as the shape.

During development you can still run from Terminal:

```bash
swift run VoicePower
```

The default toggle hotkey is `Control + Option + Space`.

The app also supports hold-to-talk on the right `Command` key. Press and hold right `Command`, speak, then release it to stop and enqueue that dictation.

If right `Command` does nothing, grant Input Monitoring permission to the current VoicePower app bundle in `System Settings > Privacy & Security > Input Monitoring`.

During development, rebuilds replace the app bundle. Re-add Accessibility permission after switching to a newly built unsigned local app if macOS stops trusting the previous grant.

The menu bar app exposes these toggles directly:

- `Settings…`
- `Cleanup: On/Off`
- `Auto Punctuation: On/Off`
- `Save Audio: On/Off`
- `Prepare Runtime`

The `Settings…` window lets you choose:

- Whisper model
- Cleanup model
- Cleanup on/off
- Auto punctuation on/off
- Save recorded audio on/off

Cleanup does not require Ollama anymore. The app runs cleanup locally through its app-managed MLX runtime.

If you start a second recording while a previous one is still being transcribed or cleaned, VoicePower now processes the recordings in FIFO order instead of letting them race each other.

## Recommended cleanup models

The default cleanup worker is tuned for:

- preserve meaning
- preserve mixed English and Chinese
- never translate
- only convert Chinese output to simplified Chinese
- optionally add punctuation safely

## Current limitations

- Text insertion is paste-based, so clipboard restore is best-effort for plain text only.
- First launch is slower because the app may need to create its local Python runtime and download models.
- Right-`Command` hold-to-talk depends on Input Monitoring permission in addition to Microphone and Accessibility.
- This is not a true IME yet. It is a global dictation helper.
- No VAD or streaming transcription yet.
- The embedded cleanup backend uses `mlx-lm`, so behavior still depends on which small model you configure.

## Next steps

Likely improvements after this first pass:

- Streaming transcription.
- Better clipboard preservation.
- Signed / notarized distribution.
- Better setup UX than menu-only status lines.
