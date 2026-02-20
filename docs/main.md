# Main — App Entry Point & ChatScreen UI

**File:** [`lib/main.dart`](../lib/main.dart)  
**Part of:** [Fluens Documentation Index](../README.md#services)

---

## Overview

`main.dart` is the application entry point and contains the entire UI layer of Fluens. It defines:

- `MyApp` — the root `MaterialApp` widget.
- `UIChatMessage` — a lightweight UI-layer message model.
- `ChatScreen` / `_ChatScreenState` — the single-screen stateful chat interface.

The UI is intentionally kept in one file with all business logic delegated to the services layer.

---

## `UIChatMessage`

```dart
class UIChatMessage {
  final String text;
  final bool isUser;    // true = user bubble, false = AI bubble
  final DateTime timestamp;
}
```

A display-only model used to render messages in the chat list. Not stored persistently — the source of truth for conversation history is `ChatService._conversationHistory`.

---

## `MyApp`

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fluen',
    theme: ThemeData(primarySwatch: Colors.deepPurple, ...),
    home: const ChatScreen(),
    debugShowCheckedModeBanner: false,
  );
}
```

Simple root widget. Applies the deep-purple theme and mounts `ChatScreen` as the only route.

---

## `_ChatScreenState` — State Fields

| Field | Type | Description |
|---|---|---|
| `_chatService` | `ChatService` | Orchestrates all inference |
| `_ttsService` | `TtsService` | Speaks AI responses aloud |
| `_httpService` | `HttpService` | Communicates with ESP32 |
| `_textController` | `TextEditingController` | Bound to the chat input field |
| `_scrollController` | `ScrollController` | Auto-scrolls the message list |
| `_messages` | `List<UIChatMessage>` | UI display message list |
| `_currentAIResponse` | `String` | Accumulates the current streaming AI response |
| `_isLoading` | `bool` | Controls loading overlay visibility |
| `_downloadProgress` | `double` | Model download/load progress (0.0–100.0) |
| `_statusMessage` | `String` | Status bar text shown above the chat |
| `_isModelLoaded` | `bool` | Whether a model is currently loaded in memory |

---

## Initialization — `initState` / `_initializeApp`

`initState` creates `HttpService` with an `onMessageReceived` callback, then calls `_initializeApp()`.

`_initializeApp()` runs the following sequence:

```
1. _ttsService.init()
2. _chatService.initialize()
      → SettingsService.init()
      → ModelDownloadService.initialize() (permissions + directory)
      → registers custom templates
      → inserts system message into history
3. If model exists → _loadModel()
   Else → show "Load from Local" prompt
4. Subscribe to _chatService.messageStream
5. Subscribe to _chatService.generatingStateStream
6. Subscribe to _chatService.modelUnloadStream
```

### `messageStream` Listener

Processes tokens from `ChatService` using sentinel patterns:

| Token Pattern | Action |
|---|---|
| Starts with `"User:"` | Extracts user text, adds `UIChatMessage(isUser: true)`, opens new AI bubble |
| Starts with `"Error:"` or `"\nError:"` | Replaces last AI bubble with error text |
| `"\n"` (end of response) | If TTS enabled → `_ttsService.speak(_currentAIResponse)`; if ESP32 connected → `_httpService.sendResponse()`; resets accumulator |
| Any other token | Appends to `_currentAIResponse`; updates last AI bubble in-place |

---

## Model Management

### `_loadFromLocal()`

Opens the `ModelDownloadService` file picker, then automatically calls `_loadModel()` if a path is returned.

### `_loadModel()`

Delegates to `ChatService.loadModel()` with `onProgress` and `onStatus` callbacks that update `_downloadProgress` and `_statusMessage`. After completion, queries `ChatService.isModelLoaded()` to set `_isModelLoaded`.

### `_unloadModel()`

Calls `ChatService.unloadModel()` and resets `_isModelLoaded` to `false`.

---

## Dialogs & Settings

### `_showConnectDialog()`

**ESP32 connection dialog** with two modes:

1. **Auto-discovery:** Starts `HttpService.startScan()` immediately. Renders a `StreamBuilder` on `discoveredDeviceStream` that shows a spinner while scanning and a `ListTile` with a "Connect" button once a device is found.
2. **Manual entry:** A `TextField` pre-filled with `192.168.4.1` (the ESP32 SoftAP default). The user can type any IP/hostname.

On connect: calls `HttpService.connect(url)` + `stopScan()` + pops the dialog.  
On disconnect: calls `HttpService.disconnect()`.

### `_showSettingsDialog()`

Full-featured settings bottom sheet / dialog built with `StatefulBuilder`. Contains sections for:

| Section | Controls |
|---|---|
| **Online inference** | Toggle "Use Groq", Groq API Key field |
| **Generation** | Max tokens, temperature, top-p, top-k, repeat penalty |
| **Model** | Context size (128–8192), chat template dropdown |
| **Custom templates** | "Create New Template" button, list of saved templates with edit/delete |
| **System message** | Multi-line text field |
| **Thinking mode** | Toggle for QwQ / DeepSeek-R1 `<think>` blocks |
| **TTS** | Toggle text-to-speech |
| **Auto-unload** | Toggle + timeout field |
| **Danger zone** | Reset all settings to default |

On "Save", all changed values are persisted via `ChatService` update methods (which call `SettingsService` internally).

### `_showCustomTemplateEditor()`

A dialog for creating or editing a custom prompt template. Includes:
- **Template name field** (disabled when editing to prevent key collision).
- **Placeholder reference** — `{system}`, `{user}`, `{assistant}`.
- **Examples panel** pre-showing Mistral, Llama-3, and a simple format as copy reference.
- **Monospace content editor**.

On save: calls `ChatService.addCustomTemplate(name, content)`, closes the editor, and reopens the settings dialog to show the updated template list.

---

## App Bar Actions

| Icon | Action |
|---|---|
| `Icons.router` | Opens `_showConnectDialog()` (green tint when connected) |
| `Icons.settings` | Opens `_showSettingsDialog()` |
| `Icons.delete_outline` | Calls `ChatService.clearHistory()` and clears `_messages` |

---

## Chat Input Bar

```
[ Text field ] [ Send / Stop button ]
```

The send button shows:
- `Icons.stop` (red) when `_chatService.isGenerating == true` → calls `ChatService.stopGeneration()`.
- `Icons.send` otherwise → calls `ChatService.sendMessage(text)` and clears the field.

The input field is disabled while `_isLoading` is true (model loading in progress).

---

## Status Bar

A persistent row above the chat list showing:
- `_statusMessage` — current app status (e.g., `"Model loaded successfully!"`, `"No model found..."`).
- A `LinearProgressIndicator` that appears when `_isLoading == true` and `_downloadProgress > 0`.
- A `"Load from Local"` chip button visible when no model is loaded.
- A `"Unload"` chip visible when a model is loaded, to manually free memory.

---

## Related Docs

- [ChatService](chat_service.md)
- [HttpService](http_service.md)
- [TtsService](tts_service.md)
- [SettingsService](settings_service.md)
- [ModelDownloadService](model_download_service.md)
