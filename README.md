<p align="center">
  <img src="assets/icon.png" alt="Fluens Logo" width="120"/>
</p>

<h1 align="center">Fluens</h1>

<p align="center">
  <strong>LLM Inference Engine · Local & Remote · Built for Fluens Hardware</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-SDK%20%5E3.11-00B4AB?logo=dart" alt="Dart"/>
  <img src="https://img.shields.io/badge/Platform-Android-green?logo=android" alt="Android"/>
  <img src="https://img.shields.io/badge/Version-1.0.0-orange" alt="Version"/>
  <img src="https://img.shields.io/badge/License-Private-red" alt="License"/>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Screenshots](#screenshots)
- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Services](#services)
  - [ChatService](#chatservice)
  - [GroqService](#groqservice)
  - [HttpService](#httpservice)
  - [ModelDownloadService](#modeldownloadservice)
  - [SettingsService](#settingsservice)
  - [TtsService](#ttsservice)
- [Supported Models & Templates](#supported-models--templates)
- [ESP32 Hardware Integration](#esp32-hardware-integration)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Configuration](#configuration)
- [Development & Testing](#development--testing)
- [Dependencies](#dependencies)

---

## Overview

**Fluens** is a Flutter-based Android application that serves as a full LLM inference engine, designed to interface seamlessly with the **Fluens ESP32 hardware**. It supports two inference modes:

- **Local (On-Device)** — Runs quantized GGUF models directly on the Android device using `llama_flutter_android`, powered by llama.cpp.
- **Online (Groq API)** — Routes conversations to the Groq cloud API, giving access to large models such as `llama-3.3-70b-versatile` with low latency.

Voice from the ESP32 hardware is received over the local network, processed by the LLM, and the AI response is optionally spoken back via the built-in Text-to-Speech engine.

---

## Screenshots

> Screenshots will be added soon.

---

## Features

| Feature | Description |
|---|---|
| **On-Device Inference** | Run GGUF models locally using llama.cpp via `llama_flutter_android` |
| **Groq Cloud Inference** | Stream responses from Groq's API (llama-3.3-70b-versatile) |
| **ESP32 Integration** | Auto-discover and poll ESP32 hardware on the local network via UDP + HTTP |
| **Chat Template Auto-Detection** | Automatically selects the correct prompt template based on model filename |
| **Multi-Turn Conversation** | Maintains full conversation history with configurable context window |
| **Streaming Token Output** | Tokens are streamed in real-time to the UI as they are generated |
| **Text-to-Speech** | AI responses are optionally read aloud using the device TTS engine |
| **Stop Generation** | Cancel any in-progress generation mid-stream |
| **Auto-Unload Model** | Automatically unloads the model after a configurable inactivity timeout (default 60 s) |
| **Thinking Mode** | Exposes raw `<think>` reasoning blocks for compatible models (QwQ, DeepSeek-R1) |
| **Custom Templates** | Define and persist your own prompt templates via Settings |
| **Persistent Settings** | All preferences stored via `SharedPreferences` and survive app restarts |

---

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                Fluens App (Flutter/Android)                    │
│                                                                │
│   ┌───────────────────┐        ┌─────────────────────────┐     │
│   │   UI (main.dart)  │◄──────►│      ChatService        │     │
│   │   ChatScreen      │        │  (orchestration layer)  │     │
│   └───────────────────┘        └───────┬─────────────────┘     │
│                                        │                       │
│             ┌──────────────────────────┼──────────────┐        │
│             ▼                          ▼              ▼        │
│   ┌─────────────────┐  ┌─────────────────────┐  ┌──────────┐   │
│   │  GroqService    │  │ ModelDownloadService│  │TtsService│   │
│   │ (Groq Cloud API)│  │  (GGUF file picker) │  │  (TTS)   │   │
│   └─────────────────┘  └─────────────────────┘  └──────────┘   │
│                                                                │
│   ┌─────────────────────┐  ┌─────────────────────────────┐     │
│   │   HttpService       │  │       SettingsService       │     │
│   │  (ESP32 comms,      │  │    (SharedPreferences)      │     │
│   │   UDP discovery,    │  └─────────────────────────────┘     │
│   │   HTTP polling)     │                                      │
│   └──────────┬──────────┘                                      │
└──────────────┼─────────────────────────────────────────────────┘
               │ Local Network
               ▼
      ┌─────────────────┐
      │  ESP32 Hardware │
      │ (Fluens Device) │
      └─────────────────┘
```

---

## Project Structure

```
fluens/
├── lib/
│   ├── main.dart                   # App entry point, ChatScreen UI
│   └── services/
│       ├── chat_service.dart       # Core inference orchestration
│       ├── groq_service.dart       # Groq cloud API client (streaming)
│       ├── http_service.dart       # ESP32 communication (UDP + HTTP polling)
│       ├── model_download_service.dart  # GGUF model file management
│       ├── settings_service.dart   # Persistent app settings
│       └── tts_service.dart        # Text-to-speech wrapper
├── assets/
│   └── icon.png                    # App icon / logo
├── scripts/
│   ├── esp32_mock_server.py        # Python mock ESP32 server for development
│   └── requirements.txt            # Python dependencies for the mock server
├── docs/
│   ├── README.md                   # Documentation index
│   ├── main.md                     # ChatScreen UI docs
│   ├── chat_service.md             # ChatService module docs
│   ├── groq_service.md             # GroqService module docs
│   ├── http_service.md             # HttpService module docs
│   ├── model_download_service.md   # ModelDownloadService module docs
│   ├── settings_service.md         # SettingsService module docs
│   └── tts_service.md              # TtsService module docs
├── android/                        # Android-specific configuration
├── pubspec.yaml                    # Flutter dependencies and metadata
└── README.md
```

---

## Services

> **Full per-module documentation** is available in the [`docs/`](docs/README.md) folder.

### ChatService

[`lib/services/chat_service.dart`](lib/services/chat_service.dart) · [Full docs →](docs/chat_service.md)

The central orchestration layer of the app. It manages:

- **Model lifecycle** — loading, unloading, and auto-unloading GGUF models via `llama_flutter_android`.
- **Inference routing** — switches between local on-device inference and Groq cloud API based on `isOnlineMode`.
- **Chat template management** — auto-detects the correct template (ChatML, Llama-3, etc.) from the model filename, or applies a user-selected or custom template.
- **Conversation history** — maintains a `List<ChatMessage>` with an 80% context-usage rule to prevent overflow.
- **Streaming** — exposes `messageStream`, `generatingStateStream`, `contextInfoStream`, and `modelUnloadStream` for reactive UI updates.
- **Generation control** — supports stop/cancel of any in-progress generation.
- **Auto-unload timer** — configurable idle timer that unloads the model to free RAM.

```dart
final chatService = ChatService();
await chatService.initialize();
await chatService.loadModel(...);
chatService.sendMessage('Hello!'); // auto-selects correct template
```

---

### GroqService

[`lib/services/groq_service.dart`](lib/services/groq_service.dart) · [Full docs →](docs/groq_service.md)

Streams AI responses from the [Groq API](https://console.groq.com), using Server-Sent Events (SSE).

- Default model: `llama-3.3-70b-versatile`
- Supports full conversation history in the request payload
- Requires a Groq API key set in Settings
- Throws a descriptive `Exception` on API errors or missing key
- `getModels()` helper fetches available models from the Groq endpoint

---

### HttpService

[`lib/services/http_service.dart`](lib/services/http_service.dart) · [Full docs →](docs/http_service.md)

Handles all communication with the Fluens ESP32 hardware over a local Wi-Fi network.

**UDP Auto-Discovery**
- Broadcasts `FLUENS_DISCOVER` packets to `255.255.255.255:12345` every second.
- Listens for `FLUENS_ESP32_HERE:<port>` responses from ESP32 devices.
- Emits discovered device URLs via `discoveredDeviceStream`.

**HTTP Polling**
- Once connected, polls `GET /messages` on the ESP32 every 2 seconds.
- Deduplicates messages using a message ID.
- Sends AI responses back to the ESP32 via `POST /response`.
- Calls `onMessageReceived(message)` callback to feed messages into the LLM pipeline.

---

### ModelDownloadService

[`lib/services/model_download_service.dart`](lib/services/model_download_service.dart) · [Full docs →](docs/model_download_service.md)

Manages GGUF model files on the Android device.

- Requests `storage` and `manageExternalStorage` permissions (Android 13+ compatible).
- Uses `file_picker` to let the user browse and select any `.gguf` file.
- Validates the selected file exists and is at least 10 MB.
- Exposes `modelPath` for the `ChatService` to load into llama.cpp.

---

### SettingsService

[`lib/services/settings_service.dart`](lib/services/settings_service.dart) · [Full docs →](docs/settings_service.md)

Persists all app preferences using `SharedPreferences`.

| Setting | Key | Default | Description |
|---|---|---|---|
| Context Size | `context_size` | `2048` | Token context window (128–8192) |
| Chat Template | `chat_template` | `auto` | Prompt template to use |
| Auto-Unload Model | `auto_unload_model` | `true` | Unload model after inactivity |
| Auto-Unload Timeout | `auto_unload_timeout` | `60 s` | Seconds before auto-unload |
| System Message | `system_message` | `"You are a helpful AI assistant..."` | Initial system prompt |
| Thinking Mode | `thinking_mode` | `false` | Show `<think>` blocks (QwQ, DeepSeek-R1) |
| TTS Enabled | `tts_enabled` | `false` | Read AI responses aloud |
| Groq API Key | `groq_api_key` | `""` | Your Groq API key |
| Groq Model | `groq_model` | `llama-3.3-70b-versatile` | Groq model to use |

Custom chat templates are also stored here, keyed by name.

---

### TtsService

[`lib/services/tts_service.dart`](lib/services/tts_service.dart) · [Full docs →](docs/tts_service.md)

Thin wrapper around `flutter_tts` for speaking AI responses.

- Language: `en-US`, speech rate `0.5`, pitch `1.0`, volume `1.0`
- Automatically truncates text to 3900 characters to stay within Android TTS limits
- Exposes `isSpeaking` state and `stop()` method
- Integrates with the `ChatService` TTS-enabled flag

---

## Supported Models & Templates

Templates are auto-detected from the model filename, but can be manually overridden in Settings.

| Template ID | Format | Models |
|---|---|---|
| `auto` | Auto-detect | All (detection by filename) |
| `chatml` | ChatML | Qwen, Qwen2, Qwen2.5, and derivatives |
| `llama3` | Llama-3 | Meta Llama 3.x series |
| `llama2` | Llama-2 | Meta Llama 2.x series |
| `phi` | Phi | Microsoft Phi-2, Phi-3 |
| `gemma` / `gemma2` / `gemma3` | Gemma | Google Gemma series |
| `alpaca` | Alpaca | Alpaca-format instruction models |
| `vicuna` | Vicuna | Vicuna-format instruction models |
| `mistral` / `mixtral` | Mistral | Mistral, Mixtral MoE models |
| `qwq` | ChatML + thinking | QwQ reasoning model |
| `deepseek-r1` | DeepSeek-R1 | DeepSeek-R1 reasoning model |
| `deepseek-v3` | DeepSeek-V3 | DeepSeek-V3 chat model |
| `deepseek-coder` | DeepSeek-Coder | DeepSeek Coder models |

Custom templates can be added and saved via the in-app Settings screen.

---

## ESP32 Hardware Integration

Fluens is designed to work with a companion ESP32 microcontroller (the **Fluens Hardware**). The communication flow is:

```
ESP32 → (UDP Broadcast) → App discovers device
ESP32 → (HTTP POST /messages) → App polls for new messages
App   → (LLM inference) → generates AI response
App   → (HTTP POST /response) → sends response back to ESP32
App   → (TTS) → optionally speaks the response aloud
```

### Mock Server (Development)

A Python mock server is included in [`scripts/esp32_mock_server.py`](scripts/esp32_mock_server.py) to simulate the ESP32 responses during development without physical hardware.

**Setup:**

```bash
cd scripts
pip install -r requirements.txt
python esp32_mock_server.py
```

The mock server:
- Listens for `FLUENS_DISCOVER` UDP broadcasts and responds appropriately.
- Serves `GET /messages` with configurable test messages.
- Accepts `POST /response` and logs the AI's reply.

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) `^3.11.0`
- Android device or emulator (API 24+)
- A GGUF-format quantized model file (e.g., from [Hugging Face](https://huggingface.co/models?library=gguf))
- *(Optional)* A [Groq API key](https://console.groq.com) for online inference mode

### Installation

```bash
# 1. Clone the repository
git clone <repo-url>
cd fluens

# 2. Install Flutter dependencies
flutter pub get

# 3. Connect an Android device (or start an emulator)
flutter devices

# 4. Run the app
flutter run
```

### Configuration

**Local Inference**

1. Download a GGUF model from Hugging Face (recommended: Qwen2.5-1.5B-Instruct-Q4_K_M.gguf or similar small model for mobile).
2. Transfer the file to your Android device.
3. In the app, tap **"Load from Local"** and select the `.gguf` file.
4. The model will be loaded — tap the chat input to start.

**Online Inference (Groq)**

1. Open **Settings** in the app.
2. Enter your Groq API key.
3. Enable **Online Mode** in the chat screen.

**ESP32 Hardware**

Ensure the ESP32 and your Android device are on the same Wi-Fi network. The app will auto-discover the device on startup using UDP broadcast.

---

## Development & Testing

Run the Python mock ESP32 server to test hardware integration without physical hardware:

```bash
cd scripts
pip install -r requirements.txt
python esp32_mock_server.py --port 8080
```

Then, in the app, connect manually or wait for the UDP auto-discovery to find `127.0.0.1:8080` (if testing on emulator/localhost).

---

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `llama_flutter_android` | `^0.1.1` | On-device GGUF inference via llama.cpp |
| `dio` | `^5.7.0` | HTTP client (model download) |
| `path_provider` | `^2.1.5` | App directory paths |
| `permission_handler` | `^11.0.1` | Android runtime permissions |
| `file_picker` | `^8.1.2` | GGUF model file selection |
| `shared_preferences` | `^2.2.2` | Persistent settings storage |
| `flutter_tts` | `^4.2.5` | Text-to-speech output |
| `flutter_webrtc` | `^1.3.0` | WebRTC support |
| `http` | `^1.6.0` | Network requests (Groq API, ESP32 polling) |

---

<p align="center">
  Built with ❤️ using Flutter · Powered by llama.cpp & Groq
</p>
