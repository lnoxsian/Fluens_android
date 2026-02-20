# Fluens — Documentation Index

This folder contains module-level technical documentation for every major component of the Fluens Flutter app.

---

## Modules

| Module | Source File | Description |
|---|---|---|
| [Main / ChatScreen UI](main.md) | `lib/main.dart` | App entry point, single-screen chat UI, all dialog logic |
| [ChatService](chat_service.md) | `lib/services/chat_service.dart` | Central orchestration: model lifecycle, inference routing, conversation history, streaming |
| [GroqService](groq_service.md) | `lib/services/groq_service.dart` | Online inference via Groq cloud API (SSE streaming) |
| [HttpService](http_service.md) | `lib/services/http_service.dart` | ESP32 hardware communication: UDP auto-discovery, HTTP polling |
| [ModelDownloadService](model_download_service.md) | `lib/services/model_download_service.dart` | GGUF model file management, permissions, file picker |
| [SettingsService](settings_service.md) | `lib/services/settings_service.dart` | Persistent app settings via SharedPreferences |
| [TtsService](tts_service.md) | `lib/services/tts_service.dart` | Text-to-speech output wrapper |

---

## Quick Links

- [Back to README](../README.md)
- [Supported Models & Templates](../README.md#supported-models--templates)
- [ESP32 Hardware Integration](../README.md#esp32-hardware-integration)
- [Getting Started](../README.md#getting-started)
