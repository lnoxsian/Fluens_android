# ChatService

**File:** [`lib/services/chat_service.dart`](../lib/services/chat_service.dart)  
**Part of:** [Fluens Documentation Index](../README.md#services)

---

## Overview

`ChatService` is the **central orchestration layer** of the Fluens app. It sits between the UI and the underlying inference backends (llama.cpp on-device via `llama_flutter_android`, or the Groq cloud API). Every conversation lifecycle event — model loading, message sending, streaming tokens back to the UI, history management, and automatic model unloading — is coordinated here.

---

## Class Definition

```dart
class ChatService {
  // Core dependencies
  final ModelDownloadService _downloadService;
  final SettingsService _settingsService;
  late final GroqService _groqService;
  LlamaController? _llama;

  // Streams exposed to the UI
  Stream<String> get messageStream;
  Stream<bool> get generatingStateStream;
  Stream<ContextInfo> get contextInfoStream;
  Stream<bool> get modelUnloadStream;

  // Public state
  bool get isLoadingModel;
  bool get isGenerating;
  bool get ttsEnabled;
  bool get isOnlineMode;
}
```

---

## Streams

| Stream | Type | Description |
|---|---|---|
| `messageStream` | `Stream<String>` | Emits tokens as they are generated. Includes sentinel strings like `"User: ..."`, `"\n"` (end of response), and `"Error: ..."` |
| `generatingStateStream` | `Stream<bool>` | Emits `true` when generation starts, `false` when it ends or is cancelled |
| `contextInfoStream` | `Stream<ContextInfo>` | Emits context window usage info (tokens used / context size / percentage) |
| `modelUnloadStream` | `Stream<bool>` | Fires once when the model is auto-unloaded due to inactivity |

---

## Initialization

```dart
await chatService.initialize({String? systemMessage});
```

Must be called before any other method. This:

1. Initialises `SettingsService` (loads `SharedPreferences`).
2. Creates `GroqService` with the loaded settings.
3. Loads inference settings: `contextSize`, `chatTemplate`, `autoUnloadModel`, `autoUnloadTimeout`, `ttsEnabled`.
4. Calls `_registerCustomTemplates()` to sync any user-defined templates with the native Kotlin layer.
5. Calls `ModelDownloadService.initialize()` — requests storage permissions and resolves the app documents directory.
6. Inserts the system message as the first entry in `_conversationHistory`.

Returns `true` if a previously selected model file still exists on disk (ready to load immediately), `false` otherwise.

---

## Model Lifecycle

### `loadModel({onProgress, onStatus})`

Loads a GGUF model from the path returned by `ModelDownloadService`.

**Steps:**
1. Checks `_isLoadingModel` guard to prevent concurrent loads.
2. Disposes any existing `LlamaController` and waits 1 second for native cleanup.
3. Validates the model file exists and is accessible.
4. Creates a new `LlamaController` instance and calls `loadModel(modelPath, threads: 4, contextSize)`.
5. Initialises a `ContextHelper` with the `80% rule` — `safeTokenLimit = contextSize * 0.8`.
6. Broadcasts initial `ContextInfo` on `contextInfoStream`.

**Callbacks:**
- `onProgress(double percent)` — called by the llama.cpp load progress stream.
- `onStatus(String message)` — called at each stage to surface human-readable status text to the UI.

### `isModelLoaded() → Future<bool>`

Delegates to `LlamaController.isModelLoaded()`. Returns `false` if `_llama` is null.

### `unloadModel()`

Disposes the `LlamaController`, clears the reference, cancels the auto-unload timer and emits `false` on `modelUnloadStream`.

### Auto-Unload

When `autoUnloadModel` is `true` (default), every call to `sendMessage()` resets a `Timer` set to `autoUnloadTimeout` seconds (default `60`). If no message is sent before the timer fires, `unloadModel()` is called automatically.

---

## Inference

### Local Inference — `sendMessage(String message, {String? template})`

1. Resets the auto-unload timer.
2. Checks `_isGenerating` guard.
3. Routes to `_sendMessageOnline()` if `isOnlineMode` is `true`.
4. **Context check (80% rule):** Estimates token count of the new message. If `projectedTotal > safeTokenLimit`, calls `_handleContextOverflow()` which trims old messages and re-opens context.
5. Truncates conversation history to last 20 messages (keeping system message) via `_truncateHistoryIfNeeded(20)`.
6. Adds the user message to `_conversationHistory` and emits `"User: $message\nAI: "` on `messageStream`.
7. Calculates `maxTokens` using `_calculateSafeMaxTokens()`.
8. Calls `LlamaController.generateChat(messages, maxTokens, temperature, topP, topK, repeatPenalty, seed, template)`.
9. Consumes the token stream with a **120-second timeout**. Each token is:
   - Stripped of `U+FFFD` replacement characters.
   - Checked for consecutive repetition (max 5 repeats before force-stop).
   - Checked for pathological tokens (`"None"`, empty strings) that suggest KV-cache corruption.
   - Emitted on `messageStream`.
10. On stream completion, adds the full assistant response to `_conversationHistory` and emits `"\n"` as the end-of-response sentinel.
11. Broadcasts updated `ContextInfo`.

**Error handling:** If the stream raises a `decode` error (common with KV-cache shifting on long conversations), a descriptive error message is emitted to the UI and generation state is always reset in `finally`.

### Online Inference — `_sendMessageOnline(String message)`

Routes to `GroqService.sendMessageStream()` with the conversation history (minus the system message, which is passed separately). Tokens are forwarded directly to `messageStream`. On completion, the assistant response is added to `_conversationHistory`.

### `stopGeneration()`

1. Sets `_isCancelled = true` — the token loop checks this flag on every iteration.
2. Cancels the stream subscription.
3. Calls `LlamaController.stop()` to signal the native layer.
4. Resets `_isGenerating` and broadcasts `false` on `generatingStateStream`.

---

## Conversation History Management

```dart
final List<ChatMessage> _conversationHistory;
```

`ChatMessage` has `role` (`"system"`, `"user"`, `"assistant"`) and `content` fields.

| Method | Behaviour |
|---|---|
| `clearHistory()` | Removes all messages except the system message. Resets context size to default. |
| `setSystemMessage(String)` | Replaces or inserts the `system` entry at index 0 |
| `updateSystemMessage(String)` | Same as above but also persists to `SettingsService` |
| `_truncateHistoryIfNeeded(int max)` | Keeps system message + the most recent `max - 1` messages |
| `_handleContextOverflow()` | Called when 80% rule is breached — trims oldest non-system messages |

---

## Chat Template Management

Templates control how the conversation history is formatted into a prompt string before passing to the model.

```dart
Future<void> updateChatTemplate(String template);
Future<List<String>> getSupportedTemplates();
Future<void> addCustomTemplate(String name, String content);
Future<void> removeCustomTemplate(String name);
```

Supported built-in template IDs: `auto`, `chatml`, `llama3`, `llama2`, `phi`, `gemma`, `gemma2`, `gemma3`, `alpaca`, `vicuna`, `mistral`, `mixtral`, `qwq`, `deepseek-r1`, `deepseek-v3`, `deepseek-coder`.

Custom templates are persisted in `SettingsService` and registered with the native Kotlin layer via `LlamaController.registerCustomTemplate(name, content)` on both add and at app startup.

---

## Settings Pass-through

`ChatService` exposes convenience setters that update both the in-memory field and persist the change via `SettingsService`:

```dart
updateContextSize(int)       // 128–8192 tokens
updateChatTemplate(String)
updateAutoUnloadModel(bool)
updateAutoUnloadTimeout(int) // >= 10 seconds
updateTtsEnabled(bool)
resetSettingsToDefault()
```

---

## Generation Configuration

```dart
GenerationConfig generationConfig = const GenerationConfig();
```

`GenerationConfig` is a value object from `llama_flutter_android` containing:

| Field | Default | Description |
|---|---|---|
| `temperature` | `0.8` | Sampling temperature |
| `topP` | `0.95` | Nucleus sampling probability |
| `topK` | `40` | Top-K sampling |
| `repeatPenalty` | `1.1` | Repetition penalty |
| `seed` | `null` | Random seed for reproducibility |

---

## Internal Helpers

| Method | Description |
|---|---|
| `_registerCustomTemplates()` | Syncs all stored custom templates from `SettingsService` to the native layer on startup |
| `_broadcastContextInfo()` | Reads `LlamaController.getContextInfo()` and emits on `contextInfoStream` |
| `_calculateSafeMaxTokens()` | Returns `safeTokenLimit - tokensUsed` to avoid exceeding the context window |
| `_resetAutoUnloadTimer()` | Cancels the existing timer and starts a new one. No-op if `autoUnloadModel` is `false` |

---

## Dependencies

| Dependency | Role |
|---|---|
| `ModelDownloadService` | Provides the model file path |
| `SettingsService` | All persistent settings |
| `GroqService` | Online inference via Groq API |
| `LlamaController` (`llama_flutter_android`) | On-device GGUF inference |

---

## Related Docs

- [GroqService](groq_service.md)
- [ModelDownloadService](model_download_service.md)
- [SettingsService](settings_service.md)
- [TtsService](tts_service.md)
- [HttpService](http_service.md)
- [Main / ChatScreen UI](main.md)
