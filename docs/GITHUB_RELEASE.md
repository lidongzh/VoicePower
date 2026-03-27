# GitHub Metadata

## Suggested Repository Description

Local macOS voice typing app for mixed English and Chinese dictation, powered by MLX Whisper with optional local cleanup and push-to-talk menu bar controls.

## Suggested Topics

`macos`, `swift`, `whisper`, `mlx`, `speech-to-text`, `dictation`, `voice-typing`, `apple-silicon`, `menubar-app`

## Suggested Release Title

`VoicePower 0.2.0`

## Suggested Release Notes

VoicePower is a local macOS menu bar app for mixed English and Chinese dictation.

What is included in this release:

- Local Whisper transcription on Apple Silicon via MLX
- Optional local cleanup model for filler-word removal and punctuation
- Simplified Chinese normalization without translating English spans
- Global hotkey plus right-Command hold-to-talk
- FIFO queueing for back-to-back dictation jobs
- First-launch runtime bootstrap and on-demand model downloads
- Native Settings window for selecting Whisper and cleanup models

Installation:

1. Download `VoicePower.dmg`
2. Drag `VoicePower.app` into `Applications`
3. Open the app and grant:
   - Microphone
   - Accessibility
   - Input Monitoring for right-Command hold-to-talk
4. Wait for the app to prepare the local runtime and download the Whisper model
5. Optional: turn `Cleanup` on from the menu bar to download the local cleanup model

Notes:

- Apple Silicon only
- Unsigned / non-notarized development release
- First launch requires network access for dependency and model downloads
- Cleanup runs locally through the bundled MLX runtime and does not require Ollama
