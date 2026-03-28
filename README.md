# VoicePower

VoicePower is a macOS menu bar dictation app for mixed English and Chinese input. It records audio locally, transcribes it with either a local MLX Whisper runtime or Groq, optionally runs a cleanup model, can normalize Chinese output to simplified Chinese, and pastes the final text into the active app.

This project is intentionally closer to "push to talk and paste" than a full input method. The goal is a small, practical desktop tool rather than a full IME.

## Current State

- Menu bar only. No Dock icon and no main document window.
- Global hotkey support.
- Right `Command` hold-to-talk support.
- FIFO recording queue, so back-to-back dictations do not race each other.
- Per-stage provider selection:
  - transcription: `Local` or `Groq`
  - cleanup: `Local` or `Groq`
- Vocabulary correction UI with row-based mappings.
- Groq API key storage in macOS Keychain, not in the JSON config file.

## Pipeline

The current pipeline is:

1. Record a mono WAV file locally.
2. Transcribe with:
   - local MLX Whisper, or
   - Groq Whisper API
3. Apply vocabulary corrections.
4. Normalize to simplified Chinese if enabled.
   - this step remains local
5. Optionally run cleanup.
   - local MLX cleanup model, or
   - Groq chat completion model
6. Paste the result with `Cmd+V`.

## Providers

### Transcription

Local transcription uses MLX Whisper models managed by the app runtime.

Groq transcription currently exposes these curated options in Settings:

- `whisper-large-v3-turbo`
- `whisper-large-v3`

Custom Groq model IDs can also be entered manually.

### Cleanup

Local cleanup uses MLX language models managed by the app runtime.

Groq cleanup currently exposes these curated options in Settings:

- `llama-3.1-8b-instant`
- `qwen/qwen3-32b`
- `llama-3.3-70b-versatile`

Custom Groq model IDs can also be entered manually.

For `qwen/qwen3-32b`, the app now explicitly requests non-thinking mode through the Groq API and also strips any unexpected `<think>` output defensively.

## Runtime Behavior

VoicePower only prepares the local runtime when a local stage still needs it.

Examples:

- If transcription is `Groq`, cleanup is `Groq`, and simplified-Chinese normalization is off:
  - local worker is not used
  - local runtime is not needed
- If transcription is `Groq`, cleanup is `Groq`, and simplified-Chinese normalization is on:
  - the local worker is still not used
  - the local runtime is still needed for normalization
- If either transcription or cleanup is `Local`:
  - the local runtime is needed
  - the worker is started only when required

The app status lines and Settings window reflect those distinctions with states such as `Ready`, `Not Used`, `Not Needed`, and `Remote (Groq)`.

## Setup

### Build

Build the app bundle:

```bash
./scripts/build_app.sh
```

Build a distributable DMG:

```bash
./scripts/build_dmg.sh
```

During development you can also run:

```bash
swift run VoicePower
```

### First Launch

1. Open `dist/VoicePower.app` or mount `dist/VoicePower.dmg`.
2. Grant:
   - Microphone
   - Accessibility
   - Input Monitoring if you want right-`Command` hold-to-talk
3. Open `Settings…`.
4. Choose providers and models.
5. If either stage uses Groq, save a Groq API key in Settings.
6. If either stage uses Local, let the app prepare the local runtime and models.

If `~/.voice-power/config.json` does not exist, VoicePower creates it automatically using [Configuration/voice-power.example.json](Configuration/voice-power.example.json) as the starting shape.

## Settings

The current Settings window includes:

- runtime, worker, transcription, and cleanup status lines
- transcription provider picker
- transcription model picker
- cleanup provider picker
- cleanup model picker
- custom model fields for both stages
- cleanup enable toggle
- auto punctuation toggle
- save recorded audio toggle
- Groq API key field with save and clear controls
- vocabulary editor with add/remove rows and explicit save

The Settings window is scrollable because the panel now contains more controls than fit at smaller window heights.

## Configuration

Config is stored at:

```text
~/.voice-power/config.json
```

Important points:

- Groq API keys are not stored in this file.
- Provider selection is stored per stage.
- Vocabulary mappings are stored as structured entries.

Example config fields:

```json
{
  "transcription": {
    "provider": "local",
    "model": "mlx-community/whisper-large-v3-turbo",
    "language": "auto"
  },
  "cleanup": {
    "enabled": false,
    "provider": "local",
    "model": "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
    "temperature": 0.0,
    "autoPunctuation": true
  }
}
```

## Hotkeys

- Default toggle hotkey: `Control + Option + Space`
- Hold-to-talk: press and hold right `Command`, speak, then release

If right `Command` does nothing, enable Input Monitoring for the current VoicePower app bundle in:

`System Settings > Privacy & Security > Input Monitoring`

## Privacy Notes

- Local transcription and local cleanup keep inference on-device.
- Groq transcription sends recorded audio to Groq.
- Groq cleanup sends cleanup text to Groq.
- Groq API keys are stored in Keychain.
- Vocabulary entries stay on the local machine.

If full local-only behavior matters, keep transcription and cleanup on `Local`.

## Current Limitations

- Text insertion is still paste-based, so clipboard restoration is best-effort for plain text.
- First launch can be slow when the app needs to create the local Python runtime and download models.
- Simplified-Chinese normalization is still local-only.
- This is not a true IME yet.
- No streaming transcription or VAD yet.
- Cleanup quality still depends heavily on the chosen model.

## Notes For Development

- Rebuilding unsigned local app bundles can invalidate previous macOS Accessibility trust, so you may need to re-grant permissions after replacing the app.
- The menu bar includes `Prepare Runtime`, `Reload Config`, and `Settings…` for quick iteration.
